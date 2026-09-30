// Errol's stand-in: it listens on the Unix socket and runs the sessions.
//
// Each connection carries one request. A tool call from an app waits here
// until its side has something to hear: the other side's message, the end
// of the session, or its cue to open. While it waits, the broker sends a
// progress line every few seconds and watches for the MCP server closing
// the connection, which means the app cancelled the call. When the
// session's hold runs out it answers "still waiting" instead, so no call
// outlives what the app will wait for. The console shows the conversation
// as it happens; run/logs/broker.jsonl records every call with its timing,
// and run/logs/transcripts/<code>.md keeps each conversation.

import Darwin
import Foundation

enum Seat: String, CaseIterable {
    case chatgpt, claude

    var name: String { self == .chatgpt ? "ChatGPT" : "Claude" }
    var other: Seat { self == .chatgpt ? .claude : .chatgpt }
}

struct RelayMessage {
    let seq: Int
    let from: Seat
    let text: String
    let done: Bool
    let at: Date
}

/// One conversation: a ticket per seat, the messages so far, and who has
/// heard what. Only touched with the broker's lock held.
final class Session {
    let code: String
    let topic: String
    let first: Seat
    let limit: Int
    let hold: TimeInterval
    let tickets: [Seat: String]
    let created = Date()
    let transcript: LogFile
    var messages: [RelayMessage] = []
    /// The newest of the other side's messages handed to each seat, which
    /// tells a first delivery from a repeat.
    var delivered: [Seat: Int] = [:]
    var hosts: [Seat: String] = [:]
    var notes: [Seat: [String]] = [:]
    var endReason: String?
    /// The newest call from each seat. An older call still waiting stands
    /// down, so a reply always goes to the call the app is listening to.
    var activeCall: [Seat: Int] = [:]

    init(code: String, topic: String, first: Seat, limit: Int, hold: TimeInterval,
         tickets: [Seat: String], transcript: LogFile) {
        self.code = code
        self.topic = topic
        self.first = first
        self.limit = limit
        self.hold = hold
        self.tickets = tickets
        self.transcript = transcript
    }

    var turn: Seat? {
        guard endReason == nil else { return nil }
        return messages.last?.from.other ?? first
    }

    /// The other side's newest message, when this seat hasn't answered it.
    func unanswered(by seat: Seat) -> RelayMessage? {
        guard let last = messages.last, last.from == seat.other else { return nil }
        return last
    }
}

final class Broker {
    enum Answer {
        case reply(text: String, outcome: String, isError: Bool)
        case cancelled
    }

    private struct CallRecord {
        let tool: String
        let host: String
        let seat: Seat?
        let code: String?
        let started: Date
    }

    let config: RelayConfig
    var progressInterval: TimeInterval = 15
    var console = true

    private let state = NSCondition()
    private var sessions: [String: Session] = [:]
    private var ticketIndex: [String: (code: String, seat: Seat)] = [:]
    private var inFlight: [Int: CallRecord] = [:]
    private var callCounter = 0
    private let events: LogFile

    init(config: RelayConfig) {
        self.config = config
        events = LogFile(directory: config.logDirectory, name: "broker.jsonl")
    }

    /// Binds the socket and serves each connection on its own thread.
    func start() throws {
        let listener = try UnixSocket.listen(at: config.socketPath)
        Thread { [self] in
            while true {
                let fd = Darwin.accept(listener, nil, nil)
                guard fd >= 0 else {
                    if errno != EINTR { usleep(100_000) }
                    continue
                }
                UnixSocket.noSignalOnWrite(fd)
                Thread { self.serve(LineChannel(fd: fd)) }.start()
            }
        }.start()
        events.append(["event": "broker.started", "socket": config.socketPath, "pid": Int(getpid())])
    }

    func serveForever() -> Never {
        do {
            try start()
        } catch {
            FileHandle.standardError.write(Data("errol-relay broker: \(error)\n".utf8))
            exit(1)
        }
        say("Broker listening on \(config.socketPath)")
        say("Logs and transcripts in \(config.logDirectory.path)")
        say("Start a session from another shell: bin/errol-relay new --topic \"…\" --open both")
        while true { sleep(86_400) }
    }

    // MARK: Connections

    private func serve(_ channel: LineChannel) {
        defer { channel.close() }
        guard let line = channel.readLine(), let request = JSON.object(line),
              let op = request["op"] as? String else { return }
        switch op {
        case "call":
            handleCall(request, channel)
        case "new", "note", "stop", "status":
            channel.writeLine(JSON.data(control(op, request)))
        default:
            channel.writeLine(JSON.data(["ok": false, "error": "unknown op \(op)"]))
        }
    }

    private func handleCall(_ request: [String: Any], _ channel: LineChannel) {
        let tool = request["tool"] as? String ?? ""
        let arguments = request["arguments"] as? [String: Any] ?? [:]
        let host = Self.hostName(request["client"])
        let started = Date()
        state.lock()
        callCounter += 1
        let callID = callCounter
        let ref = (arguments["ticket"] as? String).flatMap { ticketIndex[Self.normalize($0)] }
        inFlight[callID] = CallRecord(tool: tool, host: host, seat: ref?.seat, code: ref?.code, started: started)
        state.unlock()
        events.append([
            "event": "call.start", "call": callID, "tool": tool, "host": host,
            "mcpPid": request["pid"] ?? NSNull(), "requestId": request["requestId"] ?? NSNull(),
            "wantsProgress": request["progress"] ?? false, "session": ref?.code ?? NSNull(),
            "seat": ref?.seat.rawValue ?? NSNull(), "arguments": Self.summary(arguments),
        ])

        let answer = tool == "errol_probe_wait"
            ? probe(arguments, channel, callID)
            : relay(tool, arguments, host, channel, callID)

        let elapsed = Date().timeIntervalSince(started)
        state.lock()
        inFlight[callID] = nil
        state.unlock()
        let who = [ref?.code, ref?.seat.name ?? host].compactMap { $0 }.joined(separator: " ")
        switch answer {
        case .cancelled:
            events.append(["event": "call.cancelled", "call": callID, "tool": tool, "host": host, "after": elapsed])
            say("\(who): \(tool) (call \(callID)) cancelled by the app after \(Clock.duration(elapsed))")
        case let .reply(text, outcome, isError):
            let written = channel.writeLine(JSON.data(["kind": "result", "text": text, "isError": isError]))
            events.append([
                "event": "call.end", "call": callID, "tool": tool, "host": host, "outcome": outcome,
                "after": elapsed, "written": written,
            ])
            say("\(who): \(tool) (call \(callID)) answered after \(Clock.duration(elapsed)): \(outcome)")
        }
    }

    // MARK: The relay

    private func relay(_ tool: String, _ arguments: [String: Any], _ host: String,
                       _ channel: LineChannel, _ callID: Int) -> Answer {
        let ticket = Self.normalize(arguments["ticket"] as? String ?? "")
        state.lock()
        defer { state.unlock() }
        guard let ref = ticketIndex[ticket], let session = sessions[ref.code] else {
            return .reply(text: Wording.unknownTicket(ticket), outcome: "unknown ticket", isError: true)
        }
        let seat = ref.seat
        if let older = session.activeCall[seat], inFlight[older] != nil {
            events.append(["event": "call.superseded", "session": session.code, "seat": seat.rawValue, "older": older, "newer": callID])
        }
        session.activeCall[seat] = callID
        state.broadcast()
        switch tool {
        case "errol_join":
            if session.hosts[seat] == nil {
                session.hosts[seat] = host
                events.append(["event": "join", "session": session.code, "seat": seat.rawValue, "host": host])
                say("\(session.code) \(seat.name) joined from \(host)")
            }
            return hold(seat, session, channel, callID, briefing: true)
        case "errol_send":
            let text = (arguments["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let refusal = take(text, done: Self.flag(arguments["done"]), from: seat, in: session) {
                return refusal
            }
            return hold(seat, session, channel, callID, briefing: false)
        default:
            return hold(seat, session, channel, callID, briefing: false)
        }
    }

    /// Takes a message into the session. Returns an answer when the send
    /// can't go ahead; nil means the sender should now wait for the reply.
    private func take(_ text: String, done: Bool, from seat: Seat, in session: Session) -> Answer? {
        guard session.endReason == nil else { return nil }
        guard session.turn == seat else {
            // The same message again: the app lost the first call's result
            // and retried it. Wait for the reply as before.
            if let last = session.messages.last, last.from == seat, last.text == text {
                events.append(["event": "send.retry", "session": session.code, "seat": seat.rawValue, "seq": last.seq])
                say("\(session.code) \(seat.name) sent #\(last.seq) again; treating it as a retry")
                return nil
            }
            return .reply(text: Wording.notYourTurn(session, seat), outcome: "not your turn", isError: false)
        }
        guard !text.isEmpty else {
            return .reply(text: Wording.emptyMessage(session, seat), outcome: "empty message", isError: true)
        }
        let previous = session.messages.last
        let message = RelayMessage(seq: session.messages.count + 1, from: seat, text: text, done: done, at: Date())
        session.messages.append(message)
        record(message, in: session)
        if session.messages.count >= session.limit {
            end(session, reason: Wording.reachedLimit(session.limit), kind: "limit")
        } else if done && previous?.done == true {
            end(session, reason: Wording.bothDone, kind: "agreed")
        }
        state.broadcast()
        return nil
    }

    /// Holds a call until its seat has something to hear. Called with the
    /// lock held; the condition's wait lets go of it while the call sleeps.
    private func hold(_ seat: Seat, _ session: Session, _ channel: LineChannel, _ callID: Int,
                      briefing: Bool) -> Answer {
        let started = Date()
        let deadline = started.addingTimeInterval(session.hold)
        var nextProgress = started.addingTimeInterval(progressInterval)
        while true {
            if session.activeCall[seat] != callID {
                return .reply(text: Wording.superseded, outcome: "superseded by a newer call", isError: false)
            }
            if let message = session.unanswered(by: seat) {
                let repeated = message.seq <= session.delivered[seat, default: 0]
                session.delivered[seat] = message.seq
                if repeated {
                    events.append(["event": "redelivery", "session": session.code, "seat": seat.rawValue, "seq": message.seq])
                    say("\(session.code) delivering #\(message.seq) to \(seat.name) again (the app may have lost the first result)")
                }
                let notes = session.notes.removeValue(forKey: seat) ?? []
                return .reply(
                    text: Wording.delivery(message, to: seat, in: session, briefing: briefing, notes: notes),
                    outcome: "\(repeated ? "delivered again" : "delivered") #\(message.seq)", isError: false)
            }
            if session.endReason != nil {
                return .reply(text: Wording.ended(session), outcome: "session over", isError: false)
            }
            if session.turn == seat {
                // Nothing to answer, and it's this seat's turn: it opens.
                let notes = session.notes.removeValue(forKey: seat) ?? []
                return .reply(text: Wording.speakFirst(session, seat, briefing: briefing, notes: notes),
                              outcome: "cue to open", isError: false)
            }
            let now = Date()
            let waited = now.timeIntervalSince(started)
            if now >= deadline {
                return .reply(text: Wording.stillWaiting(session, seat, waited: waited, briefing: briefing),
                              outcome: "hold ran out", isError: false)
            }
            if channel.peerClosed() { return .cancelled }
            if now >= nextProgress {
                let line = JSON.data(["kind": "progress", "message": Wording.progress(session, seat, waited: waited)])
                guard channel.writeLine(line) else { return .cancelled }
                nextProgress = now.addingTimeInterval(progressInterval)
            }
            _ = state.wait(until: min(deadline, nextProgress, now.addingTimeInterval(0.5)))
        }
    }

    private func end(_ session: Session, reason: String, kind: String) {
        guard session.endReason == nil else { return }
        session.endReason = reason
        events.append(["event": "session.ended", "session": session.code, "kind": kind, "messages": session.messages.count])
        say("\(session.code) ended: \(reason)")
        session.transcript.append(text: "\n---\n\nThe session ended at \(Clock.time()): \(reason).\n")
        state.broadcast()
    }

    private func record(_ message: RelayMessage, in session: Session) {
        events.append([
            "event": "message", "session": session.code, "seq": message.seq, "from": message.from.rawValue,
            "chars": message.text.count, "done": message.done,
        ])
        say("\(session.code) #\(message.seq) \(message.from.name) → \(message.from.other.name) · "
            + "\(message.text.count) characters\(message.done ? " · done" : "")")
        if console {
            let body = message.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    │ \($0)" }.joined(separator: "\n")
            print(body)
            fflush(stdout)
        }
        session.transcript.append(text: "\n## \(message.seq) · \(message.from.name) · \(Clock.time(message.at))"
            + "\(message.done ? " · done" : "")\n\n\(message.text)\n")
    }

    // MARK: The timing probe

    private func probe(_ arguments: [String: Any], _ channel: LineChannel, _ callID: Int) -> Answer {
        let requested = (arguments["seconds"] as? NSNumber)?.doubleValue
            ?? Double(arguments["seconds"] as? String ?? "") ?? 60
        let seconds = min(3600, max(1, requested))
        let started = Date()
        let deadline = started.addingTimeInterval(seconds)
        var nextProgress = started.addingTimeInterval(progressInterval)
        say("probe (call \(callID)) waiting \(Clock.duration(seconds))")
        while true {
            let now = Date()
            if now >= deadline { break }
            if channel.peerClosed() { return .cancelled }
            if now >= nextProgress {
                let message = "Probe: \(Clock.duration(now.timeIntervalSince(started))) of \(Clock.duration(seconds))"
                guard channel.writeLine(JSON.data(["kind": "progress", "message": message])) else { return .cancelled }
                nextProgress = now.addingTimeInterval(progressInterval)
            }
            Thread.sleep(forTimeInterval: min(0.5, deadline.timeIntervalSince(now)))
        }
        return .reply(text: Wording.probeDone(seconds: seconds, started: started, finished: Date()),
                      outcome: "probe finished", isError: false)
    }

    // MARK: Control

    private func control(_ op: String, _ request: [String: Any]) -> [String: Any] {
        state.lock()
        defer { state.unlock() }
        switch op {
        case "new":
            let topic = (request["topic"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Wording.defaultTopic
            let first = Seat(rawValue: (request["first"] as? String ?? "chatgpt").lowercased()) ?? .chatgpt
            let limit = max(2, (request["limit"] as? NSNumber)?.intValue ?? 10)
            let hold = max(1, (request["hold"] as? NSNumber)?.doubleValue ?? 900)
            let code = uniqueCode(prefix: "S-") { sessions[$0] != nil }
            var tickets: [Seat: String] = [:]
            for seat in Seat.allCases {
                let ticket = uniqueCode(prefix: "ERR-") { ticketIndex[$0] != nil }
                tickets[seat] = ticket
                ticketIndex[ticket] = (code, seat)
            }
            let transcript = LogFile(directory: config.logDirectory.appendingPathComponent("transcripts"), name: "\(code).md")
            transcript.append(text: "# Errol session \(code)\n\nTopic: \(topic)\n\nStarted \(Clock.stamp()); "
                + "\(first.name) opens; up to \(limit) messages; calls held up to \(Clock.duration(hold)).\n")
            let session = Session(code: code, topic: topic, first: first, limit: limit, hold: hold,
                                  tickets: tickets, transcript: transcript)
            sessions[code] = session
            events.append([
                "event": "session.created", "session": code, "first": first.rawValue, "limit": limit, "hold": hold,
                "tickets": Dictionary(uniqueKeysWithValues: tickets.map { ($0.key.rawValue, $0.value) }),
            ])
            say("\(code) created: ChatGPT \(tickets[.chatgpt]!), Claude \(tickets[.claude]!), \(first.name) opens, "
                + "up to \(limit) messages, calls held up to \(Clock.duration(hold))")
            say("\(code) topic: \(topic)")
            return [
                "ok": true, "code": code, "topic": topic, "first": first.rawValue, "limit": limit, "hold": hold,
                "tickets": Dictionary(uniqueKeysWithValues: tickets.map { ($0.key.rawValue, $0.value) }),
                "prompts": Dictionary(uniqueKeysWithValues: Seat.allCases.map { ($0.rawValue, Wording.kickoff(session, $0)) }),
            ]
        case "note":
            guard let session = lookup(request["code"]) else { return ["ok": false, "error": "no such session"] }
            let text = (request["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return ["ok": false, "error": "the note is empty"] }
            let to = (request["to"] as? String ?? "both").lowercased()
            let seats = to == "both" ? Seat.allCases : Seat(rawValue: to).map { [$0] } ?? []
            guard !seats.isEmpty else { return ["ok": false, "error": "--to takes chatgpt, claude or both"] }
            seats.forEach { session.notes[$0, default: []].append(text) }
            let names = seats.map(\.name).joined(separator: " and ")
            events.append(["event": "note", "session": session.code, "to": to, "text": text])
            say("\(session.code) note for \(names): \(text)")
            session.transcript.append(text: "\n> Note from the user to \(names), \(Clock.time()): \(text)\n")
            return ["ok": true]
        case "stop":
            guard let session = lookup(request["code"]) else { return ["ok": false, "error": "no such session"] }
            end(session, reason: Wording.stoppedByUser, kind: "stopped")
            return ["ok": true]
        default:  // status
            let now = Date()
            return [
                "ok": true,
                "sessions": sessions.values.sorted { $0.created < $1.created }.map { session -> [String: Any] in
                    [
                        "code": session.code, "topic": session.topic, "messages": session.messages.count,
                        "limit": session.limit, "turn": session.turn?.name ?? "—",
                        "ended": session.endReason ?? NSNull(),
                        "hosts": Dictionary(uniqueKeysWithValues: session.hosts.map { ($0.key.name, $0.value) }),
                        "tickets": Dictionary(uniqueKeysWithValues: session.tickets.map { ($0.key.name, $0.value) }),
                    ]
                },
                "calls": inFlight.sorted { $0.key < $1.key }.map { id, call -> [String: Any] in
                    [
                        "call": id, "tool": call.tool, "host": call.host, "seat": call.seat?.name ?? NSNull(),
                        "session": call.code ?? NSNull(), "waiting": now.timeIntervalSince(call.started),
                    ]
                },
            ]
        }
    }

    // MARK: Helpers

    private func lookup(_ code: Any?) -> Session? {
        (code as? String).flatMap { sessions[$0.uppercased()] }
    }

    private func say(_ line: String) {
        guard console else { return }
        print("\(Clock.time())  \(line)")
        fflush(stdout)
    }

    private func uniqueCode(prefix: String, taken: (String) -> Bool) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        while true {
            let code = prefix + String((0..<4).map { _ in alphabet.randomElement()! })
            if !taken(code) { return code }
        }
    }

    static func normalize(_ ticket: String) -> String {
        ticket.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\"'")))
            .uppercased()
    }

    static func flag(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let string = value as? String { return string.lowercased() == "true" }
        return false
    }

    static func hostName(_ client: Any?) -> String {
        guard let info = client as? [String: Any], let name = info["name"] as? String else { return "an unnamed client" }
        return [name, info["version"] as? String].compactMap { $0 }.joined(separator: " ")
    }

    /// What the event log keeps of a call's arguments: the message's size
    /// and opening, not the whole text, which the transcript already has.
    static func summary(_ arguments: [String: Any]) -> [String: Any] {
        var summary = arguments
        if let message = arguments["message"] as? String {
            summary["message"] = String(message.prefix(80))
            summary["messageChars"] = message.count
        }
        return summary
    }
}

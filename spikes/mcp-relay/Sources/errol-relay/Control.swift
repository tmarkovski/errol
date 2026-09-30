// The command-line side of the broker: create a session, add a note, stop
// one, list what's running, or pre-fill the timing probe. `--open` puts a
// kickoff into an app's composer through its deep link, in the mode that
// `--chatgpt` (codex, work or chat) and `--claude` (code, cowork or chat)
// pick: a Code session opens in the playground folder, and a Codex-mode
// thread in whatever project ChatGPT used last. The links only pre-fill;
// the user still presses Send.

import Foundation

enum Control {
    static func run(_ command: String, _ arguments: [String], config: RelayConfig) -> Never {
        var options: [String: String] = [:]
        var positional: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                guard index + 1 < arguments.count else { fail("\(argument) needs a value") }
                options[String(argument.dropFirst(2))] = arguments[index + 1]
                index += 2
            } else {
                positional.append(argument)
                index += 1
            }
        }

        if command == "probe" {
            print(Wording.probeKickoff)
            if let open = options["open"] {
                openApps(open, prompts: [.chatgpt: Wording.probeKickoff, .claude: Wording.probeKickoff],
                         options: options, config: config)
            }
            exit(0)
        }

        var request: [String: Any] = ["op": command]
        switch command {
        case "new":
            request["topic"] = options["topic"] ?? positional.joined(separator: " ")
            request["first"] = options["first"] ?? "chatgpt"
            request["limit"] = Int(options["turns"] ?? "") ?? 10
            request["hold"] = Double(options["hold"] ?? "") ?? 900
        case "note":
            guard positional.count >= 2 else { fail("usage: errol-relay note CODE [--to chatgpt|claude|both] TEXT") }
            request["code"] = positional[0]
            request["text"] = positional.dropFirst().joined(separator: " ")
            request["to"] = options["to"] ?? "both"
        case "stop":
            guard let code = positional.first else { fail("usage: errol-relay stop CODE") }
            request["code"] = code
        default:
            break
        }
        guard let reply = send(request, config: config) else {
            fail("No broker is listening at \(config.socketPath). Start one with: spike.sh broker")
        }
        guard reply["ok"] as? Bool == true else { fail(reply["error"] as? String ?? "the broker refused the request") }
        switch command {
        case "new": printNew(reply, options: options, config: config)
        case "status": printStatus(reply)
        default: print("ok")
        }
        exit(0)
    }

    /// One request to the broker and its one-line answer.
    static func send(_ request: [String: Any], config: RelayConfig) -> [String: Any]? {
        guard let fd = try? UnixSocket.connect(to: config.socketPath) else { return nil }
        let channel = LineChannel(fd: fd)
        defer { channel.close() }
        guard channel.writeLine(JSON.data(request)), let line = channel.readLine() else { return nil }
        return JSON.object(line)
    }

    private static func printNew(_ reply: [String: Any], options: [String: String], config: RelayConfig) {
        let tickets = reply["tickets"] as? [String: String] ?? [:]
        let prompts = reply["prompts"] as? [String: String] ?? [:]
        print("Session \(reply["code"] as? String ?? "?"): ChatGPT \(tickets["chatgpt"] ?? "?"), Claude \(tickets["claude"] ?? "?")")
        for seat in Seat.allCases {
            print("\n— Kickoff for \(seat.name) —\n\(prompts[seat.rawValue] ?? "")")
        }
        if let open = options["open"] {
            var bySeat: [Seat: String] = [:]
            for seat in Seat.allCases { bySeat[seat] = prompts[seat.rawValue] }
            openApps(open, prompts: bySeat, options: options, config: config)
        }
    }

    private static func printStatus(_ reply: [String: Any]) {
        let sessions = reply["sessions"] as? [[String: Any]] ?? []
        if sessions.isEmpty { print("No sessions.") }
        for session in sessions {
            let state = (session["ended"] as? String).map { "ended: \($0)" } ?? "turn: \(session["turn"] as? String ?? "?")"
            print("\(session["code"] as? String ?? "?")  \(session["messages"] ?? 0)/\(session["limit"] ?? 0) messages  \(state)")
            print("    tickets \(session["tickets"] ?? "")  hosts \(session["hosts"] ?? "")")
        }
        for call in reply["calls"] as? [[String: Any]] ?? [] {
            let waiting = (call["waiting"] as? NSNumber)?.doubleValue ?? 0
            let who = [call["session"] as? String, call["seat"] as? String].compactMap { $0 }.joined(separator: " ")
            print("call \(call["call"] ?? "?")  \(call["tool"] ?? "?")  \(who.isEmpty ? (call["host"] as? String ?? "") : who)  waiting \(Clock.duration(waiting))")
        }
    }

    private static func openApps(_ which: String, prompts: [Seat: String], options: [String: String],
                                 config: RelayConfig) {
        for seat in Seat.allCases where which == "both" || which == seat.rawValue {
            let mode = options[seat.rawValue] ?? (seat == .chatgpt ? "codex" : "code")
            guard let prompt = prompts[seat],
                  let url = deepLink(for: seat, mode: mode, prompt: prompt, config: config) else {
                fail("\(seat.name) has no mode \"\(options[seat.rawValue] ?? "")\"")
            }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [url.absoluteString]
            try? open.run()
            open.waitUntilExit()
            print("\nPut the kickoff into \(seat.name)'s composer (\(mode)). Press Send there to start.")
        }
    }

    /// ChatGPT reads `mode` (chat, work or codex) on `codex://new`. Claude
    /// opens Code at `claude://code/new` with a folder, and Chat or Cowork
    /// at `claude://claude.ai/new`, whose handler reads `q`, `surface` and
    /// `composer`, and counts `surface=cowork` as a new Cowork conversation.
    static func deepLink(for seat: Seat, mode: String, prompt: String, config: RelayConfig) -> URL? {
        var components = URLComponents()
        switch (seat, mode) {
        case (.chatgpt, "codex"), (.chatgpt, "work"), (.chatgpt, "chat"):
            components.scheme = "codex"
            components.host = "new"
            components.queryItems = [URLQueryItem(name: "prompt", value: prompt), URLQueryItem(name: "mode", value: mode)]
        case (.claude, "code"):
            components.scheme = "claude"
            components.host = "code"
            components.path = "/new"
            components.queryItems = [
                URLQueryItem(name: "q", value: prompt),
                URLQueryItem(name: "folder", value: config.spikeRoot.appendingPathComponent("playground").path),
            ]
        case (.claude, "cowork"), (.claude, "chat"):
            components.scheme = "claude"
            components.host = "claude.ai"
            components.path = "/new"
            components.queryItems = [URLQueryItem(name: "q", value: prompt), URLQueryItem(name: "surface", value: mode)]
        default:
            return nil
        }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("errol-relay: \(message)\n".utf8))
        exit(1)
    }
}

// A broker in this process on a scratch socket, two copies of the MCP
// server as child processes speaking JSON-RPC over stdio, and scripted
// sessions played through them: the relay's rules checked end to end
// without either app.

import Darwin
import Foundation

enum SelfTest {
    static func run() -> Bool {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("errol-relay-selftest-\(getpid())")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let config = RelayConfig(socketPath: scratch.appendingPathComponent("s.sock").path,
                                 logDirectory: scratch.appendingPathComponent("logs"), spikeRoot: scratch)
        let broker = Broker(config: config)
        broker.progressInterval = 0.4
        broker.console = false
        do { try broker.start() } catch {
            print("FAIL  the broker didn't start: \(error)")
            return false
        }

        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL")  \(label)")
            if !condition { failures.append(label) }
        }
        func says(_ text: String?, _ needles: String...) -> Bool {
            guard let text = text else { return false }
            return needles.allSatisfy { text.contains($0) }
        }
        func control(_ request: [String: Any]) -> [String: Any] { Control.send(request, config: config) ?? [:] }

        guard let chatgpt = try? TestClient(config: config), let claude = try? TestClient(config: config) else {
            print("FAIL  couldn't start the MCP servers")
            return false
        }
        defer {
            chatgpt.stop()
            claude.stop()
        }

        for (client, name) in [(chatgpt, "selftest-codex"), (claude, "selftest-claude")] {
            let initialize = client.request("initialize", [
                "protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                "clientInfo": ["name": name, "version": "0"],
            ])
            let server = ((client.response(initialize)?["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"]
            check(server as? String == "errol-relay", "\(name): initialize names the server")
            client.notify("notifications/initialized", [:])
            let list = client.response(client.request("tools/list", [:]))
            let tools = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            check(Set(tools ?? []) == Tools.names, "\(name): tools/list offers the four tools")
        }

        // Session one: ChatGPT opens, and both agree to finish.
        let one = control(["op": "new", "topic": "Selftest topic", "first": "chatgpt", "limit": 10, "hold": 1.5])
        let tickets = one["tickets"] as? [String: String] ?? [:]
        let a = tickets["chatgpt"] ?? "", b = tickets["claude"] ?? ""
        check(!a.isEmpty && !b.isEmpty && a != b, "a new session hands out a ticket per side")

        let early = claude.call("errol_join", ["ticket": b], progress: true)
        check(says(claude.text(early), "ChatGPT hasn't joined", "errol_wait"), "joining before the other side hears it hasn't joined, once the hold runs out")
        check(claude.progressCount() >= 1, "a held call sends progress notifications")

        check(says(chatgpt.text(chatgpt.call("errol_join", ["ticket": a])), "Topic from the user: Selftest topic", "You speak first"),
              "the side that opens gets the briefing and its cue")

        let opening = chatgpt.call("errol_send", ["ticket": a, "message": "Opening from ChatGPT"])
        check(says(claude.text(claude.call("errol_wait", ["ticket": b])), "<message from=\"ChatGPT\">\nOpening from ChatGPT\n</message>", "message 1 of 10", "Your turn"),
              "a wait carries the other side's opening, marked off from Errol's words")

        var reply = claude.call("errol_send", ["ticket": b, "message": "Reply from Claude"])
        check(says(chatgpt.text(opening), "Reply from Claude", "message 2 of 10"), "a pending send returns the other side's reply")
        check(says(chatgpt.text(chatgpt.call("errol_wait", ["ticket": a])), "Reply from Claude"),
              "waiting again hands over the unanswered message again")

        let stray = claude.call("errol_send", ["ticket": b, "message": "Out of turn"])
        check(says(claude.text(stray), "isn't your turn"), "a send out of turn is refused")
        check(says(claude.text(reply), "replaced this one"), "the newer call makes the older waiting one stand down")

        reply = claude.call("errol_send", ["ticket": b, "message": "Reply from Claude"])
        Thread.sleep(forTimeInterval: 0.3)  // the retry reaches the broker before ChatGPT's next message
        _ = control(["op": "note", "code": one["code"] ?? "", "to": "claude", "text": "Keep it short"])
        let second = chatgpt.call("errol_send", ["ticket": a, "message": "Second from ChatGPT"])
        check(says(claude.text(reply), "Second from ChatGPT", "message 3 of 10", "Note from the user, through Errol: Keep it short"),
              "a repeated send is a retry: it waits for the reply, carries the note, and adds no message")

        chatgpt.notify("notifications/cancelled", ["requestId": second, "reason": "selftest"])
        check(chatgpt.response(second, within: 1.5) == nil, "a cancelled call gets no response")
        let closing = claude.call("errol_send", ["ticket": b, "message": "Claude thinks we're done", "done": true])
        check(says(chatgpt.text(chatgpt.call("errol_wait", ["ticket": a])), "Claude thinks we're done", "thinks the discussion is finished"),
              "after a cancel, the next wait still gets the reply, flagged as closing")
        check(says(chatgpt.text(chatgpt.call("errol_send", ["ticket": a, "message": "Agreed", "done": true])), "session is over", "both marked"),
              "a second done in a row ends the session for its sender")
        check(says(claude.text(closing), "Agreed", "That was the last message"), "the other side gets the final message and the ending")
        check(says(chatgpt.text(chatgpt.call("errol_wait", ["ticket": a])), "session is over"), "calls after the end hear that it's over")

        // Session two: Claude opens, and the limit ends it.
        let two = control(["op": "new", "topic": "Limit", "first": "claude", "limit": 2, "hold": 1.5])
        let t2 = two["tickets"] as? [String: String] ?? [:]
        check(says(claude.text(claude.call("errol_join", ["ticket": t2["claude"] ?? ""])), "You speak first"), "Claude opens the second session")
        let join = chatgpt.call("errol_join", ["ticket": t2["chatgpt"] ?? ""])
        let first = claude.call("errol_send", ["ticket": t2["claude"] ?? "", "message": "First of two"])
        check(says(chatgpt.text(join), "You've joined", "Claude opened", "First of two"), "a join that waited brings the briefing and the opening")
        check(says(chatgpt.text(chatgpt.call("errol_send", ["ticket": t2["chatgpt"] ?? "", "message": "Second of two"])), "limit of 2"),
              "the message that reaches the limit ends the session for its sender")
        check(says(claude.text(first), "Second of two", "limit of 2"), "the other side gets the last message and the limit")

        // Session three: the user stops it.
        let three = control(["op": "new", "topic": "Stop", "first": "chatgpt", "limit": 10, "hold": 5])
        let t3 = three["tickets"] as? [String: String] ?? [:]
        _ = chatgpt.text(chatgpt.call("errol_join", ["ticket": t3["chatgpt"] ?? ""]))
        let held = chatgpt.call("errol_send", ["ticket": t3["chatgpt"] ?? "", "message": "Anyone there?"])
        Thread.sleep(forTimeInterval: 0.3)
        _ = control(["op": "stop", "code": three["code"] ?? ""])
        check(says(chatgpt.text(held), "session is over", "the user stopped it"), "stopping a session releases a waiting call")
        check(says(claude.text(claude.call("errol_join", ["ticket": t3["claude"] ?? ""])), "Anyone there?", "the user stopped it"),
              "the other side still gets the message sent before the stop")

        // Tickets, the probe, and a broker that isn't there.
        let unknown = chatgpt.call("errol_join", ["ticket": "ERR-ZZZZ"])
        check(says(chatgpt.text(unknown), "doesn't know") && chatgpt.isError(unknown), "an unknown ticket is an error result")
        let probe = chatgpt.call("errol_probe_wait", ["seconds": 1], progress: true)
        check(says(chatgpt.text(probe), "waited 1 seconds"), "the probe waits and returns")
        let long = claude.call("errol_probe_wait", ["seconds": 30])
        Thread.sleep(forTimeInterval: 0.5)
        claude.notify("notifications/cancelled", ["requestId": long])
        Thread.sleep(forTimeInterval: 1.5)
        let journal = (try? String(contentsOf: config.logDirectory.appendingPathComponent("broker.jsonl"), encoding: .utf8)) ?? ""
        let cancelledProbe = journal.split(separator: "\n").compactMap { JSON.object(Data($0.utf8)) }
            .contains { $0["event"] as? String == "call.cancelled" && $0["tool"] as? String == "errol_probe_wait" }
        check(cancelledProbe, "the broker hears when the app cancels a call")

        var orphanConfig = config
        orphanConfig.socketPath = scratch.appendingPathComponent("nobody.sock").path
        if let orphan = try? TestClient(config: orphanConfig) {
            _ = orphan.response(orphan.request("initialize", ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "orphan"]]))
            let call = orphan.call("errol_join", ["ticket": a])
            check(says(orphan.text(call), "Errol isn't running") && orphan.isError(call), "without a broker, a call says Errol isn't running")
            orphan.stop()
        }

        print(failures.isEmpty ? "\nAll checks passed." : "\n\(failures.count) check(s) failed.")
        print("Logs: \(config.logDirectory.path)")
        return failures.isEmpty
    }
}

/// Plays an app's side: starts `errol-relay mcp` and speaks JSON-RPC to it.
final class TestClient {
    private let process = Process()
    private let toServer = Pipe()
    private let fromServer = Pipe()
    private let state = NSCondition()
    private var responses: [Int: [String: Any]] = [:]
    private var notifications: [[String: Any]] = []
    private var nextID = 0

    init(config: RelayConfig) throws {
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["mcp"]
        var environment = ProcessInfo.processInfo.environment
        environment["ERROL_RELAY_SOCKET"] = config.socketPath
        environment["ERROL_RELAY_LOG_DIR"] = config.logDirectory.path
        process.environment = environment
        process.standardInput = toServer
        process.standardOutput = fromServer
        process.standardError = FileHandle.nullDevice
        try process.run()
        let reader = LineChannel(fd: fromServer.fileHandleForReading.fileDescriptor)
        Thread { [weak self] in
            while let line = reader.readLine() {
                guard let message = JSON.object(line) else { continue }
                self?.receive(message)
            }
        }.start()
    }

    private func receive(_ message: [String: Any]) {
        state.lock()
        if message["method"] == nil, let id = (message["id"] as? NSNumber)?.intValue {
            responses[id] = message
        } else {
            notifications.append(message)
        }
        state.broadcast()
        state.unlock()
    }

    func request(_ method: String, _ params: [String: Any]) -> Int {
        state.lock()
        nextID += 1
        let id = nextID
        state.unlock()
        write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        return id
    }

    func notify(_ method: String, _ params: [String: Any]) {
        write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    func call(_ tool: String, _ arguments: [String: Any], progress: Bool = false) -> Int {
        var params: [String: Any] = ["name": tool, "arguments": arguments]
        if progress { params["_meta"] = ["progressToken": UUID().uuidString] }
        return request("tools/call", params)
    }

    func response(_ id: Int, within seconds: TimeInterval = 5) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(seconds)
        state.lock()
        defer { state.unlock() }
        while responses[id] == nil {
            if !state.wait(until: deadline) { break }
        }
        return responses[id]
    }

    /// The text of a tool result, or nil when none arrives in time.
    func text(_ id: Int, within seconds: TimeInterval = 5) -> String? {
        guard let result = response(id, within: seconds)?["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    func isError(_ id: Int) -> Bool {
        (response(id, within: 0)?["result"] as? [String: Any])?["isError"] as? Bool ?? false
    }

    func progressCount() -> Int {
        state.lock()
        defer { state.unlock() }
        return notifications.filter { $0["method"] as? String == "notifications/progress" }.count
    }

    func stop() {
        try? toServer.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func write(_ message: [String: Any]) {
        var data = JSON.data(message)
        data.append(0x0A)
        toServer.fileHandleForWriting.write(data)
    }
}

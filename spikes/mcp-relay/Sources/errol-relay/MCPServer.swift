// The stdio MCP server each app starts from the plugin.
//
// It keeps no conversation state. Every tool call becomes one connection
// to the broker (Errol's stand-in), and the broker's answer comes back as
// the tool result, so all of the relay's wording and rules live in one
// place. While the broker holds a call it sends a progress line every few
// seconds, which goes out as a progress notification when the app asked
// for them. A call the app cancels closes its connection, which is how the
// broker hears about it. Every JSON-RPC message in and out lands in
// run/logs/mcp-<pid>.jsonl, which is the spike's record of what each app
// actually sends.

import Darwin
import Foundation

final class MCPServer {
    private let config: RelayConfig
    private let input = LineChannel(fd: STDIN_FILENO)
    private let output = LineChannel(fd: STDOUT_FILENO)
    private let log: LogFile
    private let lock = NSLock()
    private var clientInfo: [String: Any] = [:]
    private var protocolVersion = "2025-06-18"
    private var calls: [String: BrokerCall] = [:]

    init(config: RelayConfig) {
        self.config = config
        log = LogFile(directory: config.logDirectory, name: "mcp-\(getpid()).jsonl")
    }

    func run() -> Never {
        log.append([
            "note": "started", "pid": Int(getpid()), "parent": parentCommand(),
            "cwd": FileManager.default.currentDirectoryPath, "socket": config.socketPath, "version": spikeVersion,
        ])
        while let line = input.readLine() {
            guard !line.isEmpty else { continue }
            log.append(["in": String(decoding: line.prefix(8_000), as: UTF8.self)])
            guard let message = JSON.object(line) else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            handle(message)
        }
        // The app closed stdin: it quit, or it's done with this server.
        log.append(["note": "stdin closed, exiting"])
        lock.lock()
        let open = Array(calls.values)
        lock.unlock()
        open.forEach { $0.abandon() }
        exit(0)
    }

    private func handle(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }  // a response; this server sends no requests
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            lock.lock()
            clientInfo = params["clientInfo"] as? [String: Any] ?? [:]
            if let requested = params["protocolVersion"] as? String { protocolVersion = requested }
            let info = clientInfo
            let version = protocolVersion
            lock.unlock()
            log.append([
                "note": "initialize", "clientInfo": info, "protocolVersion": version,
                "capabilities": params["capabilities"] ?? [String: Any](),
            ])
            respond(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "errol-relay", "title": "Errol relay (spike)", "version": spikeVersion],
                "instructions": Wording.serverInstructions,
            ])
        case "ping":
            respond(id, [String: Any]())
        case "tools/list":
            respond(id, ["tools": Tools.definitions])
        case "tools/call":
            // Registered here, on the reading thread, so a cancellation that
            // follows right behind the call always finds it.
            let key = Self.key(id)
            let call = BrokerCall(socketPath: config.socketPath)
            lock.lock()
            calls[key] = call
            lock.unlock()
            Thread { self.callTool(id: id, key: key, call: call, params: params) }.start()
        case "notifications/cancelled":
            let key = Self.key(params["requestId"])
            lock.lock()
            let call = calls[key]
            lock.unlock()
            log.append(["note": "cancelled", "requestId": key, "reason": params["reason"] ?? NSNull(), "inFlight": call != nil])
            call?.abandon()
        default:
            if id != nil { respondError(id, code: -32601, message: "Method not found: \(method)") }
        }
    }

    private func callTool(id: Any?, key: String, call: BrokerCall, params: [String: Any]) {
        defer {
            lock.lock()
            calls[key] = nil
            lock.unlock()
            call.finish()
        }
        let name = params["name"] as? String ?? ""
        guard Tools.names.contains(name) else {
            respondError(id, code: -32602, message: "Unknown tool: \(name)")
            return
        }
        let progressToken = (params["_meta"] as? [String: Any])?["progressToken"]
        lock.lock()
        let client = clientInfo
        let version = protocolVersion
        lock.unlock()
        let request: [String: Any] = [
            "op": "call", "tool": name, "arguments": params["arguments"] as? [String: Any] ?? [String: Any](),
            "client": client, "protocolVersion": version, "pid": Int(getpid()), "requestId": key,
            "progress": progressToken != nil,
        ]
        guard call.open(request) else {
            if !call.abandoned {
                respond(id, Tools.result(Wording.brokerUnreachable(config.socketPath), isError: true))
            }
            return
        }
        var progress = 0
        while let reply = call.next() {
            if reply["kind"] as? String == "progress" {
                guard let token = progressToken else { continue }
                progress += 1
                notify("notifications/progress", [
                    "progressToken": token, "progress": progress, "message": reply["message"] as? String ?? "",
                ])
                continue
            }
            respond(id, Tools.result(reply["text"] as? String ?? "", isError: reply["isError"] as? Bool ?? false))
            return
        }
        // A cancelled call gets no response: the app has stopped listening
        // for one, and the protocol asks servers not to send it.
        if !call.abandoned { respond(id, Tools.result(Wording.brokerHungUp, isError: true)) }
    }

    private func respond(_ id: Any?, _ result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func respondError(_ id: Any?, code: Int, message: String) {
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private func notify(_ method: String, _ params: [String: Any]) {
        send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func send(_ message: [String: Any]) {
        let data = JSON.data(message)
        log.append(["out": String(decoding: data.prefix(8_000), as: UTF8.self)])
        output.writeLine(data)
    }

    /// A request id as a dictionary key; JSON-RPC allows numbers or strings.
    static func key(_ id: Any?) -> String {
        if let string = id as? String { return "s:" + string }
        if let number = id as? NSNumber { return number.stringValue }
        return "none"
    }

    /// The executable that started this server, for the log: which of the
    /// apps' processes spawns MCP servers is one of the spike's questions.
    private func parentCommand() -> String {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "comm=", "-p", String(getppid())]
        let pipe = Pipe()
        ps.standardInput = FileHandle.nullDevice
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return "?" }
        ps.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One tool call's connection to the broker.
final class BrokerCall {
    private let socketPath: String
    private let lock = NSLock()
    private var channel: LineChannel?
    private var isAbandoned = false

    init(socketPath: String) { self.socketPath = socketPath }

    var abandoned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAbandoned
    }

    func open(_ request: [String: Any]) -> Bool {
        guard let fd = try? UnixSocket.connect(to: socketPath) else { return false }
        let channel = LineChannel(fd: fd)
        lock.lock()
        self.channel = channel
        let gone = isAbandoned
        lock.unlock()
        if gone {
            channel.shutdown()
            return false
        }
        return channel.writeLine(JSON.data(request))
    }

    func next() -> [String: Any]? {
        lock.lock()
        let channel = self.channel
        lock.unlock()
        guard let line = channel?.readLine() else { return nil }
        return JSON.object(line)
    }

    /// The app cancelled the call or went away. Shutting the connection
    /// tells the broker to stop holding it and wakes the read in next().
    func abandon() {
        lock.lock()
        isAbandoned = true
        let channel = self.channel
        lock.unlock()
        channel?.shutdown()
    }

    func finish() {
        lock.lock()
        let channel = self.channel
        self.channel = nil
        lock.unlock()
        channel?.close()
    }
}

enum Tools {
    static let names: Set<String> = ["errol_join", "errol_send", "errol_wait", "errol_probe_wait"]

    static var definitions: [[String: Any]] {
        let ticket: [String: Any] = [
            "type": "string",
            "description": "Your Errol ticket, exactly as the user gave it (for example ERR-7F3K).",
        ]
        return [
            [
                "name": "errol_join",
                "title": "Join an Errol session",
                "description": Wording.joinDescription,
                "inputSchema": [
                    "type": "object", "properties": ["ticket": ticket], "required": ["ticket"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
            ],
            [
                "name": "errol_send",
                "title": "Send a message through Errol",
                "description": Wording.sendDescription,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "ticket": ticket,
                        "message": [
                            "type": "string",
                            "description": "Your whole reply to the other assistant, in Markdown. Only this text reaches them.",
                        ],
                        "done": [
                            "type": "boolean",
                            "description": "True when you think the discussion is finished. Defaults to false.",
                        ],
                    ],
                    "required": ["ticket", "message"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false],
            ],
            [
                "name": "errol_wait",
                "title": "Keep waiting for the other assistant",
                "description": Wording.waitDescription,
                "inputSchema": [
                    "type": "object", "properties": ["ticket": ticket], "required": ["ticket"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
            ],
            [
                "name": "errol_probe_wait",
                "title": "Errol timing probe",
                "description": Wording.probeDescription,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "seconds": [
                            "type": "integer", "minimum": 1, "maximum": 3600,
                            "description": "How long to wait, in seconds.",
                        ],
                    ],
                    "required": ["seconds"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
            ],
        ]
    }

    static func result(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }
}

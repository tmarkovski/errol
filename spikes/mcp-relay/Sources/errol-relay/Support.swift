// The plumbing both halves share: where the socket and logs live, JSON
// lines over Unix sockets, and log files.

import Darwin
import Foundation

let spikeVersion = "0.1.0"

/// Where the broker listens and where both halves write their logs. The
/// plugin passes both explicitly, since the apps start the server from
/// their own working directories; the defaults sit in the spike's run/
/// folder, next to bin/.
struct RelayConfig {
    var socketPath: String
    var logDirectory: URL
    var spikeRoot: URL

    static func fromEnvironment() -> RelayConfig {
        let environment = ProcessInfo.processInfo.environment
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let root = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let run = root.appendingPathComponent("run")
        return RelayConfig(
            socketPath: environment["ERROL_RELAY_SOCKET"] ?? run.appendingPathComponent("relay.sock").path,
            logDirectory: environment["ERROL_RELAY_LOG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? run.appendingPathComponent("logs"),
            spikeRoot: root)
    }
}

enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func data(_ object: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        else { return Data(#"{"error":"unencodable"}"#.utf8) }
        return data
    }
}

enum Clock {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func time(_ date: Date = Date()) -> String { timeFormatter.string(from: date) }
    static func stamp(_ date: Date = Date()) -> String { stampFormatter.string(from: date) }

    /// "45s", "2m 05s".
    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole)s" : "\(whole / 60)m \(String(format: "%02d", whole % 60))s"
    }
}

enum UnixSocket {
    enum Failure: Error, CustomStringConvertible {
        case pathTooLong(String)
        case system(String, Int32)
        case alreadyServing(String)

        var description: String {
            switch self {
            case .pathTooLong(let path): return "the socket path is too long: \(path)"
            case .system(let call, let code): return "\(call): \(String(cString: strerror(code)))"
            case .alreadyServing(let path): return "a broker is already listening on \(path)"
            }
        }
    }

    /// Binds and listens, refusing to take the path over from a broker
    /// that is still answering on it.
    static func listen(at path: String) throws -> Int32 {
        if let probe = try? connect(to: path) {
            Darwin.close(probe)
            throw Failure.alreadyServing(path)
        }
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket", errno) }
        var address = try self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw Failure.system("bind", code)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 32) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw Failure.system("listen", code)
        }
        return fd
    }

    static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket", errno) }
        var address = try self.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            Darwin.close(fd)
            throw Failure.system("connect", code)
        }
        noSignalOnWrite(fd)
        return fd
    }

    /// A write to a connection the other end closed fails instead of
    /// raising SIGPIPE, which would kill the process.
    static func noSignalOnWrite(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}

/// Newline-framed JSON over a file descriptor: stdio for the MCP side, a
/// Unix socket between the MCP server and the broker. Reads happen on one
/// thread at a time; writes are serialized here.
final class LineChannel {
    let fd: Int32
    private var buffer = Data()
    private let writeLock = NSLock()

    init(fd: Int32) { self.fd = fd }

    /// The next line without its newline, or nil at the end of the stream.
    func readLine() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    @discardableResult
    func writeLine(_ data: Data) -> Bool {
        var framed = data
        framed.append(0x0A)
        writeLock.lock()
        defer { writeLock.unlock() }
        return framed.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    /// Whether the other end has closed the connection, checked without
    /// consuming anything and without blocking.
    func peerClosed() -> Bool {
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if count == 0 { return true }
        if count < 0 { return !(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) }
        return false
    }

    /// Ends the connection in both directions, which also wakes a read
    /// blocked on another thread; close() alone does not.
    func shutdown() { Darwin.shutdown(fd, SHUT_RDWR) }

    func close() { Darwin.close(fd) }
}

/// Appends to a file in the log folder: one JSON object per line for event
/// logs, or plain text for transcripts.
final class LogFile {
    let url: URL
    private let handle: FileHandle?
    private let lock = NSLock()

    init(directory: URL, name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func append(_ fields: [String: Any]) {
        var entry = fields
        entry["t"] = Clock.stamp()
        var line = JSON.data(entry)
        line.append(0x0A)
        write(line)
    }

    func append(text: String) { write(Data(text.utf8)) }

    private func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.write(contentsOf: data)
    }
}

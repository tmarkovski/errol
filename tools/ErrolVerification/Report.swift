import Foundation
import CryptoKit

enum CheckStatus: String, Codable { case passed, failed, blocked, inconclusive, notRun, manual }

struct VerificationCheck: Codable, Equatable {
    var name: String
    var status: CheckStatus
    var detail: String
    var required = true
}

struct CaseResult: Codable {
    var scenario: DesktopScenario
    var startedAt: Date?
    var finishedAt: Date?
    var checks: [VerificationCheck] = []
    var artifacts: [String] = []
    var status: CheckStatus {
        let required = checks.filter(\.required)
        if required.contains(where: { $0.status == .failed }) { return .failed }
        if required.contains(where: { $0.status == .blocked }) { return .blocked }
        if required.contains(where: { $0.status == .inconclusive }) { return .inconclusive }
        if required.contains(where: { $0.status == .notRun }) || finishedAt == nil || required.isEmpty ||
            scenario.requiredChecks.contains(where: { name in !required.contains(where: { $0.name == name }) }) { return .notRun }
        if required.contains(where: { $0.status == .manual }) { return .manual }
        return .passed
    }
}

struct RunEnvironment: Codable, Equatable {
    var macOS: String
    var revision: String
    var dirty: Bool
    var applications: [String: String]
    var sourceHash: String = ""
}

struct VerificationReport: Codable {
    var schemaVersion = 1
    var runID: String
    var createdAt = Date()
    var suite: String
    var filter: String?
    var totalSuiteCases: Int
    var maxCharacters: Int
    var caseTimeout: Double
    var environment: RunEnvironment
    var results: [CaseResult]
    var complete: Bool { !results.isEmpty && results.allSatisfy { $0.status == .passed } }
    var exitCode: Int32 { complete ? 0 : (results.contains { $0.status == .failed } ? 1 : 2) }

    // Computed status is serialized explicitly so a consumer cannot confuse
    // "the runner exited" with all required checks passing.
    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(self)) as! [String: Any]
        object["complete"] = complete
        object["exitCode"] = exitCode
        object["results"] = try results.map { result -> [String: Any] in
            var item = try JSONSerialization.jsonObject(with: encoder.encode(result)) as! [String: Any]
            item["status"] = result.status.rawValue
            return item
        }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        try markdown.write(to: directory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        try junit.write(to: directory.appendingPathComponent("junit.xml"), atomically: true, encoding: .utf8)
    }

    var markdown: String {
        var lines = ["# Desktop compatibility report", "", "Result: **\(complete ? "PASS" : "INCOMPLETE / FAILED")**",
                     "", "Suite: \(suite). Selected \(results.count) of \(totalSuiteCases) cases. Filter: \(filter ?? "none").",
                     "Revision: \(environment.revision)\(environment.dirty ? " (working changes)" : ""). macOS: \(environment.macOS).",
                     "", "A manual, skipped, unobservable, or unfinished required check is not an automated pass.", ""]
        for result in results {
            lines += ["## \(result.scenario.id)", "", "Status: **\(result.status.rawValue)**", ""]
            for check in result.checks {
                lines.append("- \(check.status.rawValue) · \(check.name)\(check.required ? "" : " (informational)"): \(check.detail.replacingOccurrences(of: "\n", with: " "))")
            }
            lines += result.artifacts.map { "- Artifact: [\($0)](\($0))" }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    var junit: String {
        let failures = results.filter { $0.status == .failed }.count
        let skipped = results.filter { $0.status != .passed && $0.status != .failed }.count
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                     "<testsuite name=\"\(xml(suite))\" tests=\"\(results.count)\" failures=\"\(failures)\" skipped=\"\(skipped)\">"]
        for result in results {
            lines.append("  <testcase name=\"\(xml(result.scenario.id))\">")
            let detail = result.checks.map { "\($0.status.rawValue) \($0.name): \($0.detail)" }.joined(separator: "\n")
            if result.status == .failed { lines.append("    <failure message=\"compatibility check failed\">\(xml(detail))</failure>") }
            else if result.status != .passed { lines.append("    <skipped message=\"\(result.status.rawValue)\">\(xml(detail))</skipped>") }
            lines += ["    <system-out>\(xml(detail))</system-out>", "  </testcase>"]
        }
        return (lines + ["</testsuite>"]).joined(separator: "\n")
    }
}

private func xml(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func sha256(_ text: String) -> String { sha256(Data(text.utf8)) }

struct VerificationOptions {
    var suite: DesktopSuite = .smoke
    var filter: String?
    var app: DesktopApp?
    var list = false
    var dryRun = false
    var screenshots = false
    var countdown = 5
    var timeout: Double = 180
    var cap = 12_000
    var output: String?
    var selected: [DesktopScenario] {
        suite.scenarios.filter { scenario in
            (filter == nil || scenario.id.localizedCaseInsensitiveContains(filter!)) &&
            (app == nil || scenario.endpoint.app == app || scenario.peer?.app == app)
        }
    }

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self()
        var index = 0
        func value(_ flag: String) throws -> String {
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("--") else { throw VerificationError("Missing value for \(flag)") }
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--guided": break
            case "--suite":
                let raw = try value(flag)
                guard let suite = DesktopSuite(rawValue: raw) else { throw VerificationError("Unknown suite: \(raw)") }
                options.suite = suite
            case "--filter": options.filter = try value(flag)
            case "--app":
                let raw = try value(flag)
                guard let app = DesktopApp(rawValue: raw) else { throw VerificationError("Unknown app: \(raw)") }
                options.app = app
            case "--output": options.output = try value(flag)
            case "--list": options.list = true
            case "--dry-run": options.dryRun = true
            case "--screenshots": options.screenshots = true
            case "--countdown":
                guard let n = Int(try value(flag)), (3...30).contains(n) else { throw VerificationError("Countdown must be 3–30 seconds") }
                options.countdown = n
            case "--timeout":
                guard let n = Double(try value(flag)), n.isFinite, (15...1800).contains(n) else { throw VerificationError("Timeout must be 15–1800 seconds") }
                options.timeout = n
            case "--max-chars":
                guard let n = Int(try value(flag)), (1024...100_000).contains(n) else { throw VerificationError("Character cap must be 1024–100000") }
                options.cap = n
            default: throw VerificationError("Unknown guided option: \(flag)")
            }
            index += 1
        }
        guard !options.selected.isEmpty else { throw VerificationError("No scenarios match; use --list to inspect the suite") }
        return options
    }
}

struct VerificationError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

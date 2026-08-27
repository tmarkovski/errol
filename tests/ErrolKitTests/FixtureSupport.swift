// Shared plumbing for the fixture-based scenario tests: loading recorded
// trees, running the full detection pipeline over them, and the optional
// debug dump.
//
// Debug logging is off by default. ERROL_TEST_LOG=1 swift test prints, for
// every scenario, each window's full tree (ax-dump style), how it was
// classified, and everything detection concluded — the first stop when a
// recaptured fixture starts failing and the assertion message alone doesn't
// say why.

import XCTest
@testable import ErrolKit

/// Fixture files are arrays of window trees in the ax-dump --capture schema
/// (see Core/ElementNode.swift). Current fixtures are synthesized from the
/// live-verified shapes in the README's field notes; replace them with real
/// captures (tools/ax-dump.swift <app> --capture) as app versions move.
func loadFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> [FixtureElement] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                      subdirectory: "Fixtures") else {
        XCTFail("fixture \(name).json not found in the test bundle", file: file, line: line)
        return []
    }
    do {
        return try JSONDecoder().decode([FixtureElement].self, from: Data(contentsOf: url))
    } catch {
        XCTFail("fixture \(name).json failed to decode: \(error)", file: file, line: line)
        return []
    }
}

/// Everything the pipeline concludes about one fixture, computed through the
/// same generic finders and status composition the live paths call.
struct Detection {
    var windows: [FixtureElement] = []
    var scans: [WindowScan] = []
    var excluded: [Bool] = []
    /// Index of the window chooseChatWindow targets, nil when none qualifies.
    var chosenIndex: Int?
    /// The readiness strip's verdict over all windows.
    var status = SideStatus(appName: "")
    // The rest is scoped to the chosen window, like every run-time finder.
    var affordanceLabels: [String] = []
    var copyLabels: [String] = []
    var lastAffordanceIsToggle = false
    var sendLabel: String?
    var composerLabel: String?
    var streaming = false
}

func detect(fixture name: String, selectors: AppSelectors, appName: String,
            file: StaticString = #filePath, line: UInt = #line) -> Detection {
    var detection = Detection()
    detection.windows = loadFixture(name, file: file, line: line)
    detection.scans = detection.windows.map { scanWindow($0, selectors: selectors) }
    detection.excluded = detection.windows.map { isExcludedWindow($0, selectors: selectors) }
    detection.status = composeSideStatus(appName: appName, scans: detection.scans,
                                         selectors: selectors)
    if let chosen = chooseChatWindow(from: detection.windows, selectors: selectors) {
        detection.chosenIndex = detection.windows.firstIndex(of: chosen)
        let affordances = messageAffordances(under: chosen, selectors: selectors)
        detection.affordanceLabels = affordances.map(\.label)
        detection.lastAffordanceIsToggle = affordances.last
            .map { isMessageActionsToggle($0, selectors: selectors) } ?? false
        detection.copyLabels = copyButtons(under: chosen, selectors: selectors).map(\.label)
        detection.sendLabel = sendButton(under: chosen, selectors: selectors)?.label
        detection.composerLabel = composerElement(under: chosen)?.label
        detection.streaming = hasStopButton(under: chosen, selectors: selectors)
    }
    debugDump(fixture: name, detection: detection)
    return detection
}

// MARK: - Optional debug dump

private let debugLogEnabled: Bool = {
    guard let value = ProcessInfo.processInfo.environment["ERROL_TEST_LOG"] else { return false }
    return !value.isEmpty && value != "0"
}()

private func debugDump(fixture name: String, detection: Detection) {
    guard debugLogEnabled else { return }
    var lines = ["", "==== fixture \(name) ===="]
    for (index, window) in detection.windows.enumerated() {
        let scan = detection.scans[index]
        var markers: [String] = []
        if detection.excluded[index] { markers.append("excluded") }
        if scan.hasComposer { markers.append("composer") }
        if index == detection.chosenIndex { markers.append("CHOSEN") }
        lines.append("-- window \(index) \"\(scan.title)\""
            + (markers.isEmpty ? "" : "  [\(markers.joined(separator: ", "))]"))
        lines.append("   scan: surfaceTab=\(scan.surfaceTab ?? "-")"
            + " composerSurface=\(scan.composerSurface ?? "-")"
            + " mode=\(scan.modeLabel ?? "-")"
            + " path=\(scan.surfacePath ?? "-")"
            + " model=\(scan.model ?? "-")"
            + " effort=\(scan.effort ?? "-")")
        renderTree(window, depth: 1, into: &lines)
    }
    let status = detection.status
    lines.append("status: \(status.headline)"
        + " surface=\(status.surface ?? "-") model=\(status.model ?? "-")"
        + " detail=\(status.detail ?? "-")")
    lines.append("chosen-window detection:"
        + " affordances=\(detection.affordanceLabels)"
        + " copies=\(detection.copyLabels)"
        + " send=\(detection.sendLabel ?? "-")"
        + " composer=\(detection.composerLabel ?? "-")"
        + " streaming=\(detection.streaming)")
    lines.append("")
    FileHandle.standardError.write(lines.joined(separator: "\n").data(using: .utf8)!)
}

/// ax-dump-style indented lines: role, subrole, joined label, value, url.
private func renderTree(_ node: FixtureElement, depth: Int, into lines: inout [String]) {
    var parts = ["[\(node.role ?? "?")]"]
    if let subrole = node.subrole { parts.append("(\(subrole))") }
    let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty { parts.append("\"\(label)\"") }
    switch node.value {
    case .string(let string)?: parts.append("value=\"\(string)\"")
    case .number(let number)?: parts.append("value=\(number)")
    case .bool(let flag)?: parts.append("value=\(flag)")
    case nil: break
    }
    if let url = node.urlString { parts.append("url=\(url)") }
    lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
    for child in node.children { renderTree(child, depth: depth + 1, into: &lines) }
}

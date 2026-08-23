// BotBridge
// Drives a conversation between the ChatGPT desktop app and Claude Desktop
// by pressing each app's "Copy" button and pasting into the other app's input.
//
// Build & run:
//   swift run BotBridge --seed "Hi! You're talking to another AI. Pick a topic."
//
// Requirements:
//   - Grant Accessibility permission to your TERMINAL app (Terminal/iTerm/etc):
//     System Settings > Privacy & Security > Accessibility.
//     Child processes launched from the terminal inherit its grant.
//   - Both apps must be running with a conversation window open.
//
// Useful flags:
//   --list                       print running apps + bundle IDs, then exit
//   --arrange                    tile the chat windows side by side (ChatGPT left, Claude right), then exit
//   --unarrange                  restore the frames saved by the last --arrange (or center both), then exit
//   --inspect                    dump buttons/text areas of both apps and what the selectors match, then exit
//   --press chatgpt|claude "label"  press the first button whose label contains "label", then exit (debug)
//   --turns N                    number of responses to relay (default 10)
//   --new-chats                  start a fresh chat in both apps (Cmd+N) before seeding; default is to use the open chats
//   --first chatgpt|claude       which app receives the seed (default chatgpt)
//   --seed "text"                the human's initial message, handed to the first agent
//   --seed-file path             read the initial message from a file
//   --stop-sequence "token"      reply marker that ends the run (default [[END-CONVERSATION]])
//   --timeout N                  seconds to wait for a response (default 300)
//   --max-chars N                truncate relayed messages (default 12000)
//   --transcript path            transcript output (default ./botbridge-transcript.md)
//   --chatgpt-bundle-id ID       override (default com.openai.codex; classic app is com.openai.chat)
//   --claude-bundle-id ID        override (default com.anthropic.claudefordesktop)

import AppKit
import ApplicationServices
import Foundation

// MARK: - Configuration

/// Per-app label keywords. Kept separate per app because the two UIs label
/// their affordances differently (verified against live trees, Aug 2026).
struct AppSelectors {
    /// Per-message copy button label substring.
    var copyKeyword: String
    /// Reject copy buttons whose label also contains any of these.
    var copyExcludeKeywords: [String]
    var stopKeyword = "stop"
    var sendKeyword = "send"
    /// A window containing a button or text field with any of these labels is
    /// not a chat window (e.g. Claude Code session windows inside Claude Desktop).
    var windowExcludeLabels: [String] = []
}

struct Config {
    var chatgptBundleID = "com.openai.codex"   // standalone Codex / unified app; classic ChatGPT is com.openai.chat
    var claudeBundleID = "com.anthropic.claudefordesktop"
    var turns = 10
    var first = "chatgpt"
    var newChats = false
    /// The human's initial message. The relay wraps it in a framing preamble
    /// (see openingMessage/introMessage), so this should read like an ordinary
    /// user request, not an explanation of the relay.
    var seed = "Please introduce yourselves to each other and discuss a topic you both find interesting."
    /// A reply containing this marker (or an empty reply) ends the run early.
    var stopSequence = "[[END-CONVERSATION]]"
    var timeout: TimeInterval = 300
    var maxChars = 12000
    var transcriptPath = "botbridge-transcript.md"

    // ChatGPT's response action bar uses bare "Copy"; "Copy message" (paired
    // with "Edit message") belongs to user messages, and tables/links get
    // their own qualified labels. Match bare copy, exclude the qualified ones.
    var chatgptSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["message", "table", "link", "code"])
    var claudeSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["code", "link", "table"],
        windowExcludeLabels: ["Terminal input", "New terminal", "Rewind to here"])

    var inspect = false
    var arrange = false
    var unarrange = false
    var frameStatePath = ".botbridge-frames"
    var press: (app: String, label: String)?
}

var config = Config()

// MARK: - Arg parsing

func parseArgs() {
    var args = Array(CommandLine.arguments.dropFirst())
    func take() -> String? { args.isEmpty ? nil : args.removeFirst() }
    while let arg = take() {
        switch arg {
        case "--list":
            listRunningApps()
            exit(0)
        case "--inspect":          config.inspect = true
        case "--arrange":          config.arrange = true
        case "--unarrange":        config.unarrange = true
        case "--press":
            if let app = take(), let label = take() {
                config.press = (app: app, label: label)
            } else {
                log("--press needs two values: app (chatgpt|claude) and a label substring")
                exit(1)
            }
        case "--turns":            config.turns = Int(take() ?? "") ?? config.turns
        case "--new-chats":        config.newChats = true
        case "--first":            config.first = take() ?? config.first
        case "--seed":             config.seed = take() ?? config.seed
        case "--seed-file":
            if let path = take(), let text = try? String(contentsOfFile: path, encoding: .utf8) {
                config.seed = text
            }
        case "--stop-sequence":    config.stopSequence = take() ?? config.stopSequence
        case "--timeout":          config.timeout = TimeInterval(take() ?? "") ?? config.timeout
        case "--max-chars":        config.maxChars = Int(take() ?? "") ?? config.maxChars
        case "--transcript":       config.transcriptPath = take() ?? config.transcriptPath
        case "--chatgpt-bundle-id": config.chatgptBundleID = take() ?? config.chatgptBundleID
        case "--claude-bundle-id":  config.claudeBundleID = take() ?? config.claudeBundleID
        case "--help", "-h":
            print("See header comments in main.swift for flags.")
            exit(0)
        default:
            log("Unknown flag: \(arg) (use --help)")
            exit(1)
        }
    }
}

func listRunningApps() {
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("\(app.localizedName ?? "?")  ->  \(app.bundleIdentifier ?? "?")")
    }
}

// MARK: - Logging

let iso = ISO8601DateFormatter()
func log(_ message: String) {
    print("[\(iso.string(from: Date()))] \(message)")
}

func appendTranscript(_ text: String) {
    let url = URL(fileURLWithPath: config.transcriptPath)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(text.data(using: .utf8)!)
        try? handle.close()
    }
}

// MARK: - AX helpers

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return err == .success ? value : nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func axLabel(_ element: AXUIElement) -> String {
    [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, "AXLabel"]
        .compactMap { axAttribute(element, $0) as? String }
        .joined(separator: " ")
}

func findAll(in element: AXUIElement,
             depth: Int = 0,
             maxDepth: Int = 80,
             where predicate: (AXUIElement) -> Bool,
             into results: inout [AXUIElement]) {
    guard depth <= maxDepth else { return }
    if predicate(element) { results.append(element) }
    for child in axChildren(element) {
        findAll(in: child, depth: depth + 1, maxDepth: maxDepth, where: predicate, into: &results)
    }
}

// MARK: - App discovery

struct TargetApp {
    let name: String
    let app: NSRunningApplication
    let ax: AXUIElement
    let selectors: AppSelectors
}

func requireApp(bundleID: String, name: String, selectors: AppSelectors) -> TargetApp {
    guard let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundleID }) else {
        log("ERROR: \(name) (\(bundleID)) is not running.")
        log("Launch it, open a conversation, then re-run. Use --list to inspect bundle IDs.")
        exit(1)
    }
    let ax = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 3.0)
    return TargetApp(name: name, app: running, ax: ax, selectors: selectors)
}

/// Electron apps expose an empty AX tree until nudged.
func enableElectronAccessibility(_ target: TargetApp) {
    AXUIElementSetAttributeValue(target.ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

// MARK: - Element finding

func axWindows(_ target: TargetApp) -> [AXUIElement] {
    (axAttribute(target.ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

func isExcludedWindow(_ window: AXUIElement, selectors: AppSelectors) -> Bool {
    guard !selectors.windowExcludeLabels.isEmpty else { return false }
    var hits: [AXUIElement] = []
    findAll(in: window, where: { el in
        let role = axAttribute(el, kAXRoleAttribute) as? String
        guard role == kAXButtonRole as String || role == kAXTextFieldRole as String else { return false }
        let label = axLabel(el)
        return selectors.windowExcludeLabels.contains { label.localizedCaseInsensitiveContains($0) }
    }, into: &hits)
    return !hits.isEmpty
}

func hasTextArea(_ window: AXUIElement) -> Bool {
    var areas: [AXUIElement] = []
    findAll(in: window, where: { el in
        axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String
    }, into: &areas)
    return !areas.isEmpty
}

/// The window all searches are scoped to. Re-resolved on every call so window
/// churn during a run doesn't leave us holding a dead reference. Windows with
/// exclusion markers (e.g. Claude Code sessions) are never eligible.
func chatWindow(in target: TargetApp) -> AXUIElement? {
    let eligible = axWindows(target).filter { !isExcludedWindow($0, selectors: target.selectors) }
    return eligible.first(where: hasTextArea) ?? eligible.first
}

func isCopyButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard label.localizedCaseInsensitiveContains(selectors.copyKeyword) else { return false }
    for exclude in selectors.copyExcludeKeywords
        where label.localizedCaseInsensitiveContains(exclude) { return false }
    return true
}

func isCopyButton(_ element: AXUIElement, selectors: AppSelectors) -> Bool {
    guard axAttribute(element, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
    return isCopyButtonLabel(axLabel(element), selectors: selectors)
}

func copyButtons(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    var results: [AXUIElement] = []
    findAll(in: root, where: { isCopyButton($0, selectors: target.selectors) }, into: &results)
    return results
}

func hasStopButton(in target: TargetApp) -> Bool {
    guard let root = chatWindow(in: target) else { return false }
    var results: [AXUIElement] = []
    findAll(in: root, where: { el in
        guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        return axLabel(el).localizedCaseInsensitiveContains(target.selectors.stopKeyword)
    }, into: &results)
    return !results.isEmpty
}

func sendButton(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    var results: [AXUIElement] = []
    findAll(in: root, where: { el in
        guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        return axLabel(el).localizedCaseInsensitiveContains(target.selectors.sendKeyword)
    }, into: &results)
    return results.first
}

func inputArea(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    // Prefer the focused element, but only if it lives in the chat window;
    // focus could be on another window (e.g. a Claude Code session).
    if let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute) {
        let el = focused as! AXUIElement
        if axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String,
           let window = axAttribute(el, kAXWindowAttribute),
           CFEqual(window, root) {
            return el
        }
    }
    // Otherwise take the last text area in the window (composers sit at the bottom).
    var areas: [AXUIElement] = []
    findAll(in: root, where: { el in
        let role = axAttribute(el, kAXRoleAttribute) as? String
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
    }, into: &areas)
    return areas.last
}

func composerValue(in target: TargetApp) -> String? {
    guard let input = inputArea(in: target) else { return nil }
    return axAttribute(input, kAXValueAttribute) as? String
}

// MARK: - Inspection

/// Prints, per window, every button and text input plus anything in any role
/// whose label mentions the copy keyword. This is how selector breakage gets
/// diagnosed without reaching for Xcode's Accessibility Inspector.
func inspect(_ target: TargetApp) {
    print("=== \(target.name) (\(target.app.bundleIdentifier ?? "?")) ===")
    let windows = axWindows(target)
    let chosen = chatWindow(in: target)
    print("Windows: \(windows.count)")

    for (index, window) in windows.enumerated() {
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? ""
        var status = ""
        if isExcludedWindow(window, selectors: target.selectors) {
            status = "  [excluded: not a chat window]"
        } else if let chosen, CFEqual(window, chosen) {
            status = "  [chosen chat window]"
        }
        print("\n-- Window \(index): \"\(title)\"\(status)")

        var buttons: [AXUIElement] = []
        findAll(in: window, where: {
            axAttribute($0, kAXRoleAttribute) as? String == kAXButtonRole as String
        }, into: &buttons)

        // Collapse duplicate labels so a long conversation doesn't flood the output.
        var counts: [String: Int] = [:]
        var order: [String] = []
        for button in buttons {
            let label = axLabel(button).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = label.isEmpty ? "<unlabeled>" : label
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        print("   Buttons (\(buttons.count) total, \(order.count) distinct):")
        for key in order {
            let marker = isCopyButtonLabel(key, selectors: target.selectors) ? "  <- matches copy selector" : ""
            print("     \(counts[key]!)x \(key)\(marker)")
        }

        var inputs: [AXUIElement] = []
        findAll(in: window, where: { el in
            let role = axAttribute(el, kAXRoleAttribute) as? String
            return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
        }, into: &inputs)
        print("   Text inputs (\(inputs.count)):")
        for input in inputs {
            let role = (axAttribute(input, kAXRoleAttribute) as? String) ?? "?"
            let label = axLabel(input).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (axAttribute(input, kAXValueAttribute) as? String)?.prefix(60) ?? ""
            print("     [\(role)] label=\"\(label)\" value=\"\(value)\"")
        }

        // Is message content exposed as readable text? (Decides whether the
        // relay can read responses from the tree instead of pressing copy.)
        var texts: [String] = []
        var staticTexts: [AXUIElement] = []
        findAll(in: window, where: { el in
            axAttribute(el, kAXRoleAttribute) as? String == kAXStaticTextRole as String
        }, into: &staticTexts)
        for el in staticTexts {
            if let value = axAttribute(el, kAXValueAttribute) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(value)
            }
        }
        let longest = texts.sorted { $0.count > $1.count }.prefix(3)
        print("   Static texts: \(texts.count) non-empty; longest samples:")
        for sample in longest {
            let flat = sample.replacingOccurrences(of: "\n", with: " ")
            print("     (\(sample.count) chars) \(flat.prefix(100))")
        }

        // Catch copy affordances that are not AXButton (menu items, groups, etc.).
        var copyish: [AXUIElement] = []
        findAll(in: window, where: { el in
            axAttribute(el, kAXRoleAttribute) as? String != kAXButtonRole as String
                && axLabel(el).localizedCaseInsensitiveContains("copy")
        }, into: &copyish)
        if !copyish.isEmpty {
            print("   Non-button elements mentioning \"copy\":")
            for el in copyish.prefix(20) {
                let role = (axAttribute(el, kAXRoleAttribute) as? String) ?? "?"
                let label = axLabel(el).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
                print("     [\(role)] \(label)")
            }
        }
    }

    // Menu items are hover-free AX targets; a "copy response" menu command
    // would beat chasing hover-only buttons in the message area.
    if let menuBar = axAttribute(target.ax, kAXMenuBarAttribute) {
        var items: [AXUIElement] = []
        findAll(in: menuBar as! AXUIElement, where: { el in
            axLabel(el).localizedCaseInsensitiveContains("copy")
                || ((axAttribute(el, kAXTitleAttribute) as? String) ?? "")
                    .localizedCaseInsensitiveContains("copy")
        }, into: &items)
        print("Menu items mentioning \"copy\" (\(items.count)):")
        for item in items {
            let title = (axAttribute(item, kAXTitleAttribute) as? String) ?? axLabel(item)
            let cmdChar = (axAttribute(item, "AXMenuItemCmdChar") as? String) ?? ""
            print("  \(title)\(cmdChar.isEmpty ? "" : "  [Cmd+\(cmdChar)]")")
        }
    }

    print("\nApp-wide selector results: copy=\(copyButtons(in: target).count), stop=\(hasStopButton(in: target)), input=\(inputArea(in: target) != nil ? "found" : "MISSING")")
    print("")
}

// MARK: - Activation

let systemWideAX = AXUIElementCreateSystemWide()

/// NSWorkspace.frontmostApplication is refreshed by run-loop notifications and
/// goes stale in a CLI that never spins one. The system-wide AX focused
/// application is queried live, but it proxies through the focused app, whose
/// AX server (Electron) is intermittently unresponsive; fall back to the
/// window server's front window, which needs no cooperation from the app.
func isFrontmost(_ target: TargetApp) -> Bool {
    if let focused = axAttribute(systemWideAX, kAXFocusedApplicationAttribute) {
        var pid: pid_t = -1
        AXUIElementGetPid(focused as! AXUIElement, &pid)
        return pid == target.app.processIdentifier
    }
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return false }
    for window in info {
        if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
           let pid = window[kCGWindowOwnerPID as String] as? pid_t {
            return pid == target.app.processIdentifier
        }
    }
    return false
}

/// The app that was frontmost when BotBridge started — normally the terminal
/// it was launched from — captured before any focus is moved so it can be
/// handed back when the run ends.
let launchFrontmostApp: NSRunningApplication? = {
    if let focused = axAttribute(systemWideAX, kAXFocusedApplicationAttribute) {
        var pid: pid_t = -1
        AXUIElementGetPid(focused as! AXUIElement, &pid)
        if let app = NSRunningApplication(processIdentifier: pid) { return app }
    }
    if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] {
        for window in info {
            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let pid = window[kCGWindowOwnerPID as String] as? pid_t,
               let app = NSRunningApplication(processIdentifier: pid) {
                return app
            }
        }
    }
    return NSWorkspace.shared.frontmostApplication
}()

/// Hand focus back to wherever BotBridge was launched from. Registered via
/// atexit so every exit path (done, stop sequence, error, Ctrl+C) goes
/// through it.
func refocusLaunchApp() {
    guard let app = launchFrontmostApp, let bundleID = app.bundleIdentifier else { return }
    // Skip when it never lost focus (e.g. --inspect moves no windows).
    if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] {
        for window in info {
            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let pid = window[kCGWindowOwnerPID as String] as? pid_t {
                if pid == app.processIdentifier { return }
                break
            }
        }
    }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleID]
    try? open.run()
    open.waitUntilExit()
    log("Focus returned to \(app.localizedName ?? bundleID).")
}

/// Bring the target app to the foreground and confirm it got there.
/// NSRunningApplication.activate from a background process is ignored under
/// macOS cooperative activation, so fall back to the AX frontmost attribute
/// (which honors the Accessibility grant) and raising the chat window.
func makeFrontmost(_ target: TargetApp, within seconds: TimeInterval = 6) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    var attempt = 0
    while Date() < deadline {
        if isFrontmost(target) { return true }
        switch attempt % 3 {
        case 0:
            // Ignored under cooperative activation, but free when it does work.
            target.app.activate(options: [])
        case 1:
            // Observed returning success without effect (macOS 26); kept as a
            // cheap second try on systems where it still lands.
            AXUIElementSetAttributeValue(target.ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let window = chatWindow(in: target) {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        default:
            // LaunchServices activation is the one that reliably lands from a
            // background CLI (verified: the two above are no-ops here).
            if let bundleID = target.app.bundleIdentifier {
                let open = Process()
                open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                open.arguments = ["-b", bundleID]
                try? open.run()
                open.waitUntilExit()
            }
        }
        attempt += 1
        usleep(300_000)
    }
    return isFrontmost(target)
}

// MARK: - Window arrangement

/// AX window coordinates use a top-left origin on the primary display;
/// NSScreen uses bottom-left. Convert a Cocoa rect to AX coordinates.
func axRect(_ rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens[0].frame.height
    return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY,
                  width: rect.width, height: rect.height)
}

func windowFrameDescription(_ window: AXUIElement) -> String {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = axAttribute(window, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = axAttribute(window, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return "(\(Int(position.x)),\(Int(position.y))) \(Int(size.width))x\(Int(size.height))"
}

func setWindowFrame(_ target: TargetApp, _ window: AXUIElement, origin: CGPoint, size: CGSize) {
    // AXEnhancedUserInterface (set at startup as the Electron nudge) makes
    // some apps animate or ignore AX moves; drop it for the move, restore after.
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    var origin = origin
    var size = size
    if let positionValue = AXValueCreate(.cgPoint, &origin),
       let sizeValue = AXValueCreate(.cgSize, &size) {
        // Size, position, size again: position can be clamped by the old
        // size, and the final size settles min-size adjustments.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

func currentFrame(_ window: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = axAttribute(window, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = axAttribute(window, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: position, size: size)
}

/// Snapshot the pre-tiling frames so --unarrange can put them back.
func saveFrames(_ entries: [(TargetApp, AXUIElement)]) {
    let lines = entries.map { target, window -> String in
        let frame = currentFrame(window)
        return "\(target.name)\t\(frame.origin.x)\t\(frame.origin.y)\t\(frame.width)\t\(frame.height)"
    }
    try? lines.joined(separator: "\n").write(toFile: config.frameStatePath, atomically: true, encoding: .utf8)
}

/// Restore the frames saved by the last --arrange. Without a snapshot the
/// best effort is centering both windows, lightly cascaded.
func unarrange(_ targets: [TargetApp]) {
    if let content = try? String(contentsOfFile: config.frameStatePath, encoding: .utf8) {
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 5,
                  let x = Double(parts[1]), let y = Double(parts[2]),
                  let width = Double(parts[3]), let height = Double(parts[4]),
                  let target = targets.first(where: { $0.name == parts[0] }),
                  let window = chatWindow(in: target) else { continue }
            setWindowFrame(target, window, origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
            log("restored \(target.name) to \(windowFrameDescription(window))")
        }
        try? FileManager.default.removeItem(atPath: config.frameStatePath)
        return
    }
    log("unarrange: no saved frames at \(config.frameStatePath); centering both windows instead")
    let area = axRect(NSScreen.screens[0].visibleFrame)
    let size = CGSize(width: (area.width * 0.7).rounded(), height: (area.height * 0.85).rounded())
    var cascade: CGFloat = -30
    for target in targets {
        guard let window = chatWindow(in: target) else { continue }
        let origin = CGPoint(x: (area.midX - size.width / 2 + cascade).rounded(),
                             y: (area.midY - size.height / 2 + cascade / 2).rounded())
        setWindowFrame(target, window, origin: origin, size: size)
        log("centered \(target.name) at \(windowFrameDescription(window))")
        cascade += 60
    }
}

/// Tile the two chat windows into the halves of one screen, same result as
/// the native Fill & Arrange "Left & Right", which only pairs windows
/// interactively and can't be aimed at a specific window across two apps.
func arrangeSideBySide(left: TargetApp, right: TargetApp) {
    guard let leftWindow = chatWindow(in: left), let rightWindow = chatWindow(in: right) else {
        log("arrange: could not resolve a chat window in both apps")
        return
    }
    saveFrames([(left, leftWindow), (right, rightWindow)])
    // Tile on whichever screen currently hosts the left app's window.
    var screen = NSScreen.screens[0]
    if let value = axAttribute(leftWindow, kAXPositionAttribute) {
        var position = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
        for candidate in NSScreen.screens where axRect(candidate.frame).contains(position) {
            screen = candidate
        }
    }
    let area = axRect(screen.visibleFrame)
    let half = (area.width / 2).rounded(.down)
    setWindowFrame(left, leftWindow,
                   origin: area.origin,
                   size: CGSize(width: half, height: area.height))
    setWindowFrame(right, rightWindow,
                   origin: CGPoint(x: area.origin.x + half, y: area.origin.y),
                   size: CGSize(width: area.width - half, height: area.height))
    // Raise both so they are the visible pair.
    for target in [left, right] {
        if let window = chatWindow(in: target) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        _ = makeFrontmost(target)
    }
    log("arranged on \(Int(area.width))x\(Int(area.height)): \(left.name) \(windowFrameDescription(leftWindow)), \(right.name) \(windowFrameDescription(rightWindow))")
}

// MARK: - Keyboard synthesis

func keystroke(_ virtualKey: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(30_000)
    let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
}

let keyV: CGKeyCode = 9
let keyN: CGKeyCode = 45
let keyReturn: CGKeyCode = 36

// MARK: - Core actions

/// Cmd+N opens a fresh conversation in both apps (reusing the window).
/// Confirmed fresh when no per-message copy buttons remain in the chat window.
func startNewChat(in target: TargetApp) -> Bool {
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front for Cmd+N")
        return false
    }
    keystroke(keyN, flags: .maskCommand)
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if copyButtons(in: target).isEmpty {
            log("\(target.name): new chat ready")
            return true
        }
        usleep(200_000)
    }
    log("\(target.name): WARNING: could not confirm a fresh chat, continuing in the current one")
    return true
}

func copyLastResponse(from target: TargetApp) -> String? {
    let buttons = copyButtons(in: target)
    guard let button = buttons.last else {
        log("\(target.name): no copy button found")
        return nil
    }
    let pasteboard = NSPasteboard.general
    let before = pasteboard.changeCount
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    if err != .success {
        log("\(target.name): AXPress on copy button failed (\(err.rawValue))")
        return nil
    }
    let deadline = Date().addingTimeInterval(3)
    while pasteboard.changeCount == before {
        if Date() > deadline {
            log("\(target.name): clipboard never changed after pressing copy")
            return nil
        }
        usleep(50_000)
    }
    return pasteboard.string(forType: .string)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func send(_ text: String, to target: TargetApp) -> Bool {
    var payload = text
    if payload.count > config.maxChars {
        payload = String(payload.prefix(config.maxChars)) + "\n\n[truncated by relay]"
        log("\(target.name): payload truncated to \(config.maxChars) chars")
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(payload, forType: .string)

    // Keystrokes go to the frontmost app no matter what has AX focus, so
    // never type unless the target is verified frontmost.
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front; refusing to type into another app's window")
        return false
    }

    if let input = inputArea(in: target) {
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(150_000)
    } else {
        log("\(target.name): could not locate input area, pasting into current focus")
    }

    keystroke(keyV, flags: .maskCommand)
    // Give the app time to render the paste; large messages need it before sending.
    let renderDelay = min(2_000_000, 300_000 + payload.count * 20)
    usleep(useconds_t(renderDelay))

    let beforeSend = composerValue(in: target)

    // A send button press is more reliable than a Return keystroke (no
    // Return-vs-Cmd+Return ambiguity, no dependence on keyboard focus).
    if let button = sendButton(in: target),
       AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
        log("\(target.name): sent via send button")
    } else {
        keystroke(keyReturn)
        log("\(target.name): sent via Return keystroke")
    }

    // Confirm the composer emptied; if not, escalate through the known
    // variants, re-checking frontmost before each keystroke so an app that
    // stole focus mid-send doesn't receive stray Returns.
    if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
        guard isFrontmost(target) else {
            log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
            return false
        }
        log("\(target.name): composer unchanged after send, trying Return keystroke")
        keystroke(keyReturn)
        if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
            guard isFrontmost(target) else {
                log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
                return false
            }
            log("\(target.name): composer still unchanged, trying Cmd+Return")
            keystroke(keyReturn, flags: .maskCommand)
            if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
                log("\(target.name): WARNING: could not confirm the message was sent")
            }
        }
    }
    return true
}

func waitForComposerChange(in target: TargetApp, from before: String?, within seconds: TimeInterval) -> Bool {
    // Composer value can be unreadable in some states; then there is nothing to verify.
    guard before != nil else { return true }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if composerValue(in: target) != before { return true }
        usleep(200_000)
    }
    return false
}

/// Both apps give the just-pasted user message its own copy button, so a raw
/// "count went up" check fires on the echo of our own message. Wait for that
/// echo to render and fold it into the baseline; only buttons beyond it can
/// belong to the response.
func absorbEchoIntoBaseline(in target: TargetApp, preSend: Int) -> Int {
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if copyButtons(in: target).count > preSend { return preSend + 1 }
        usleep(100_000)
    }
    return preSend
}

func waitForResponse(in target: TargetApp, baselineCopyCount: Int) -> Bool {
    log("\(target.name): waiting for response (baseline \(baselineCopyCount) copy buttons)...")
    let deadline = Date().addingTimeInterval(config.timeout)
    var stableTicks = 0
    while Date() < deadline {
        let count = copyButtons(in: target).count
        let streaming = hasStopButton(in: target)
        if count > baselineCopyCount && !streaming {
            stableTicks += 1
            if stableTicks >= 2 {
                log("\(target.name): response complete (\(count) copy buttons)")
                return true
            }
        } else {
            stableTicks = 0
        }
        usleep(1_200_000)
    }
    log("\(target.name): timed out after \(Int(config.timeout))s")
    return false
}

// MARK: - Main

// Logs must stream when stdout is a pipe (background runs), not sit in a block buffer.
setvbuf(stdout, nil, _IOLBF, 0)

parseArgs()

// Permission check, with the system prompt if not yet granted.
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
if !trusted {
    log("Accessibility permission missing.")
    log("Grant it to your terminal app in System Settings > Privacy & Security > Accessibility, then re-run.")
    exit(1)
}

let chatgpt = requireApp(bundleID: config.chatgptBundleID, name: "Codex", selectors: config.chatgptSelectors)
let claude = requireApp(bundleID: config.claudeBundleID, name: "Claude", selectors: config.claudeSelectors)
// Both apps are Chromium-based; the nudge is harmless on native apps anyway.
enableElectronAccessibility(claude)
enableElectronAccessibility(chatgpt)
usleep(700_000) // let the trees populate

// From here on the tool may move focus; give it back on any exit. (--list
// exits during arg parsing and never reaches this.)
atexit { refocusLaunchApp() }

if let press = config.press {
    let target = press.app.lowercased() == "claude" ? claude : chatgpt
    var matches: [AXUIElement] = []
    findAll(in: target.ax, where: { el in
        axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String
            && axLabel(el).localizedCaseInsensitiveContains(press.label)
    }, into: &matches)
    guard let button = matches.first else {
        log("\(target.name): no button matching \"\(press.label)\"")
        exit(1)
    }
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    log("\(target.name): pressed \"\(axLabel(button).trimmingCharacters(in: .whitespacesAndNewlines))\" (\(err == .success ? "ok" : "error \(err.rawValue)"))")
    exit(err == .success ? 0 : 1)
}

if config.arrange {
    arrangeSideBySide(left: chatgpt, right: claude)
    exit(0)
}

if config.unarrange {
    unarrange([chatgpt, claude])
    exit(0)
}

if config.inspect {
    inspect(chatgpt)
    inspect(claude)
    exit(0)
}

signal(SIGINT) { _ in
    print("\nInterrupted. Transcript: \(config.transcriptPath)")
    exit(0)
}

guard config.turns >= 1 else {
    log("--turns must be at least 1")
    exit(1)
}

// Preflight: refuse to run without an eligible chat window in each app.
// (A Claude Code session window inside Claude Desktop does not count.)
for target in [chatgpt, claude] {
    guard let window = chatWindow(in: target) else {
        log("ERROR: \(target.name): no eligible chat window found.")
        log("Open a regular chat conversation in \(target.name) and re-run. (--inspect shows how windows were classified.)")
        exit(1)
    }
    let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? "untitled"
    log("\(target.name): targeting window \"\(title)\"")
    if inputArea(in: target) == nil {
        log("ERROR: \(target.name): chat window has no composer text area.")
        exit(1)
    }
}

if config.newChats {
    for target in [chatgpt, claude] {
        guard startNewChat(in: target) else {
            log("ERROR: \(target.name): could not start a new chat.")
            exit(1)
        }
    }
}

var speaker = config.first.lowercased() == "claude" ? claude : chatgpt
var listener = speaker.app == chatgpt.app ? claude : chatgpt

// MARK: - Message framing

/// Ground rules given to each agent once, at the start of its side of the
/// conversation. Everything after these two framing messages passes through
/// verbatim.
func relayRules() -> String {
    """
    This is an automated agent-to-agent conversation: your replies are relayed \
    to another AI assistant, and its replies are relayed back to you. The human \
    who set this up is not taking part in the conversation. You can end the \
    conversation at any time by replying with an empty message or by including \
    \(config.stopSequence) anywhere in a reply.
    """
}

/// What the first agent receives: the rules plus the human's initial message.
func openingMessage() -> String {
    relayRules()
        + "\n\nThe initial message from the human user follows.\n\n---\n\n"
        + config.seed
}

/// What the second agent receives on its first turn: the rules, the human's
/// initial message, and the first agent's response to it.
func introMessage(firstReply: String, from other: TargetApp) -> String {
    relayRules() + """
    \n
    Below are the human's initial message and \(other.name)'s response to it, \
    so you have the full context. Continue the conversation by replying to \
    \(other.name).

    --- Initial message from the human ---

    \(config.seed)

    --- \(other.name)'s response ---

    \(firstReply)
    """
}

/// The agents' side of the stop protocol.
func isStopReply(_ reply: String) -> Bool {
    let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains(config.stopSequence)
}

appendTranscript("# BotBridge transcript, \(iso.string(from: Date()))\n\n")
let opener = openingMessage()
appendTranscript("## Opening message (to \(speaker.name))\n\n\(opener)\n\n")

log("Seeding \(speaker.name)...")
var baseline = copyButtons(in: speaker).count
guard send(opener, to: speaker) else { exit(1) }
baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)

for turn in 1...config.turns {
    guard waitForResponse(in: speaker, baselineCopyCount: baseline) else {
        log("Stopping: no response from \(speaker.name).")
        break
    }
    guard let reply = copyLastResponse(from: speaker) else {
        log("Stopping: could not copy response from \(speaker.name).")
        break
    }

    appendTranscript("## Turn \(turn): \(speaker.name)\n\n\(reply)\n\n")

    if isStopReply(reply) {
        log("\(speaker.name) ended the conversation (empty reply or stop sequence).")
        appendTranscript("_\(speaker.name) ended the conversation._\n\n")
        break
    }

    log("Turn \(turn)/\(config.turns): \(speaker.name) -> \(listener.name) (\(reply.count) chars)")

    if turn == config.turns {
        log("Turn cap reached.")
        break
    }

    // The listener's first message carries the rules and full context; every
    // later relay is the other agent's reply, untouched.
    let payload = turn == 1 ? introMessage(firstReply: reply, from: speaker) : reply
    baseline = copyButtons(in: listener).count
    guard send(payload, to: listener) else { break }
    baseline = absorbEchoIntoBaseline(in: listener, preSend: baseline)
    swap(&speaker, &listener)
}

log("Done. Transcript: \(config.transcriptPath)")

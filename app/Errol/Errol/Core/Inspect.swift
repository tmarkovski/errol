// The Inspect dump: per window, every button and text input plus anything
// in any role whose label mentions the copy keyword. This is how selector
// breakage gets diagnosed without reaching for Xcode's Accessibility
// Inspector; the panel's Inspect button writes it into the log.

import AppKit
import ApplicationServices

func inspectReport(_ target: TargetApp) -> String {
    var lines: [String] = []
    lines.append("=== \(target.name) (\(target.app.bundleIdentifier ?? "?")) ===")
    let windows = axWindows(target)
    let chosen = chatWindow(in: target)
    lines.append("Windows: \(windows.count)")

    for (index, window) in windows.enumerated() {
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? ""
        var status = ""
        if isExcludedWindow(window, selectors: target.selectors) {
            status = "  [excluded: not a chat window]"
        } else if let chosen, CFEqual(window, chosen) {
            status = "  [chosen chat window]"
        }
        lines.append("\n-- Window \(index): \"\(title)\"\(status)")

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
        lines.append("   Buttons (\(buttons.count) total, \(order.count) distinct):")
        for key in order {
            let marker = isCopyButtonLabel(key, selectors: target.selectors) ? "  <- matches copy selector" : ""
            lines.append("     \(counts[key]!)x \(key)\(marker)")
        }

        var inputs: [AXUIElement] = []
        findAll(in: window, where: { el in
            let role = axAttribute(el, kAXRoleAttribute) as? String
            return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
        }, into: &inputs)
        lines.append("   Text inputs (\(inputs.count)):")
        for input in inputs {
            let role = (axAttribute(input, kAXRoleAttribute) as? String) ?? "?"
            let label = axLabel(input).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (axAttribute(input, kAXValueAttribute) as? String)?.prefix(60) ?? ""
            lines.append("     [\(role)] label=\"\(label)\" value=\"\(value)\"")
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
        lines.append("   Static texts: \(texts.count) non-empty; longest samples:")
        for sample in longest {
            let flat = sample.replacingOccurrences(of: "\n", with: " ")
            lines.append("     (\(sample.count) chars) \(flat.prefix(100))")
        }

        // Catch copy affordances that are not AXButton (menu items, groups, etc.).
        var copyish: [AXUIElement] = []
        findAll(in: window, where: { el in
            axAttribute(el, kAXRoleAttribute) as? String != kAXButtonRole as String
                && axLabel(el).localizedCaseInsensitiveContains("copy")
        }, into: &copyish)
        if !copyish.isEmpty {
            lines.append("   Non-button elements mentioning \"copy\":")
            for el in copyish.prefix(20) {
                let role = (axAttribute(el, kAXRoleAttribute) as? String) ?? "?"
                let label = axLabel(el).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
                lines.append("     [\(role)] \(label)")
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
        lines.append("Menu items mentioning \"copy\" (\(items.count)):")
        for item in items {
            let title = (axAttribute(item, kAXTitleAttribute) as? String) ?? axLabel(item)
            let cmdChar = (axAttribute(item, "AXMenuItemCmdChar") as? String) ?? ""
            lines.append("  \(title)\(cmdChar.isEmpty ? "" : "  [Cmd+\(cmdChar)]")")
        }
    }

    lines.append("\nApp-wide selector results: copy=\(copyButtons(in: target).count), stop=\(hasStopButton(in: target)), input=\(inputArea(in: target) != nil ? "found" : "MISSING")")
    return lines.joined(separator: "\n")
}

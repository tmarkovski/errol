// The turn count inside the composer's end-condition chip: a bare number
// that edits in place, no box around it. It wraps NSTextField rather than
// using SwiftUI's for the three things a number in a chip should do that a
// text field does not — step on ↑ ↓, step under the scroll wheel, and take
// the keyboard with its digits selected the moment the chip opens, so the
// count can be typed over without a second click. Every keystroke that
// leaves a valid number commits it: the field never holds a value the
// controller does not. See PerchComposer for the chip it sits in.

import AppKit
import SwiftUI

struct PerchTurnsField: NSViewRepresentable {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...99
    var font: NSFont
    var color: NSColor
    /// Bumped by the owner to ask for the keyboard with the digits selected;
    /// the field acts on each new value once.
    var focusRequest = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NudgeField {
        let field = NudgeField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = font
        field.textColor = color
        field.stringValue = String(value)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = false
        field.lineBreakMode = .byClipping
        field.onNudge = { [weak coordinator = context.coordinator] step in
            coordinator?.nudge(by: step)
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NudgeField, context: Context) {
        context.coordinator.parent = self
        field.font = font
        field.textColor = color
        // Never overwrite a number mid-edit: the binding is behind the
        // keystroke that just wrote it. Outside an edit the field follows
        // the controller.
        if !context.coordinator.editing, field.stringValue != String(value) {
            field.stringValue = String(value)
        }
        if let editor = field.currentEditor() as? NSTextView {
            editor.textColor = color
            editor.insertionPointColor = color
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            // The chip may be mid-insertion when the request lands, so the
            // field takes the keyboard once it is in its window.
            DispatchQueue.main.async {
                guard field.window != nil else { return }
                field.selectText(nil)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NudgeField,
                      context: Context) -> CGSize? {
        field.intrinsicContentSize
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PerchTurnsField
        var focusRequest = 0
        var editing = false
        weak var field: NudgeField?

        init(parent: PerchTurnsField) {
            self.parent = parent
        }

        /// A step from the arrows or the wheel: clamped, committed, and left
        /// selected so the next step or keystroke replaces it.
        func nudge(by step: Int) {
            let next = clamp(parent.value + step)
            guard next != parent.value else { return }
            parent.value = next
            field?.stringValue = String(next)
            if editing { field?.currentEditor()?.selectAll(nil) }
        }

        private func clamp(_ n: Int) -> Int {
            min(max(n, parent.range.lowerBound), parent.range.upperBound)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            editing = true
            // The caret in the number's own ink, not the system's black.
            if let editor = field?.currentEditor() as? NSTextView,
               let color = field?.textColor {
                editor.insertionPointColor = color
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // Digits only, and no more of them than the top of the range has,
            // so a stray keystroke never leaves the field showing a number
            // wider than it is.
            let digits = String(field.stringValue
                .filter { $0.isASCII && $0.isNumber }
                .prefix(String(parent.range.upperBound).count))
            if digits != field.stringValue { field.stringValue = digits }
            if let n = Int(digits), parent.range.contains(n) {
                parent.value = n
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            editing = false
            guard let field = notification.object as? NSTextField else { return }
            // An emptied or out-of-range field settles to the nearest value
            // the run can use.
            let settled = clamp(Int(field.stringValue) ?? parent.value)
            parent.value = settled
            field.stringValue = String(settled)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                nudge(by: 1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                nudge(by: -1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.cancelOperation(_:)):
                // Return and Esc both mean "done here": the value is already
                // committed, so all that is left is to give the keyboard up.
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// The field itself: sized for two digits whatever it holds, first-click
/// aware inside the panel, and stepping under the scroll wheel.
final class NudgeField: NSTextField {
    var onNudge: ((Int) -> Void)?
    /// Trackpad deltas are tiny and many; they accumulate to a step.
    private var wheel: CGFloat = 0

    /// A real NSView inside the panel, so the hosting view's claim on the
    /// first click (FirstMouseHostingView) does not cover it — the same
    /// account as the composer's text view.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        let digits = NSAttributedString(
            string: "00",
            attributes: [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        ).size().width
        return NSSize(width: ceil(digits) + 4, height: base.height)
    }

    override func scrollWheel(with event: NSEvent) {
        // A flick's momentum would keep counting after the fingers lifted.
        guard event.momentumPhase.isEmpty else { return }
        if event.hasPreciseScrollingDeltas {
            wheel += event.scrollingDeltaY
            guard abs(wheel) >= 12 else { return }
        } else {
            wheel = event.scrollingDeltaY
            guard wheel != 0 else { return }
        }
        // The gesture's own direction, whatever the scrolling preference
        // says about content: fingers or wheel moving up count up.
        let up = event.isDirectionInvertedFromDevice ? wheel < 0 : wheel > 0
        wheel = 0
        onNudge?(up ? 1 : -1)
    }
}

// A multiline prompt editor that follows its content from a useful minimum
// through a bounded maximum, then scrolls. SwiftUI's TextEditor always takes
// the fixed frame it is given; wrapping NSTextView lets the prompt remain a
// real textarea (including Return for paragraph breaks) while participating
// in the panel's layout.

import AppKit
import SwiftUI

/// An explicit input lifetime, independent of SwiftUI's animated removal of
/// the editor. Ending it disables the actual text view before focus is released.
final class TextEditorSession {
    private weak var textView: NSTextView?
    private(set) var acceptsInput = false

    func begin(text: String) {
        acceptsInput = true
        // SwiftUI may reuse the native editor when an animated close is
        // followed quickly by reopening. Restore that editor in place.
        textView?.string = text
        textView?.isEditable = true
        textView?.isSelectable = true
    }

    func clear() {
        guard acceptsInput else { return }
        textView?.unmarkText()
        textView?.string = ""
    }

    func restoreFocus() {
        guard acceptsInput, let textView else { return }
        textView.window?.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView)
    }

    func attach(_ view: NSTextView) {
        if let previous = textView, previous !== view {
            previous.isEditable = false
            previous.isSelectable = false
        }
        textView = view
        view.isEditable = acceptsInput
        view.isSelectable = acceptsInput
    }

    @discardableResult
    func end() -> String? {
        acceptsInput = false
        guard let textView else { return nil }
        textView.unmarkText()
        let text = textView.string
        textView.isEditable = false
        textView.isSelectable = false
        if textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
        return text
    }
}

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    /// Shrink to this size before soft wrapping. Nil keeps a fixed font.
    var minimumFontSize: CGFloat?
    var textColor: NSColor = .labelColor
    /// Nil keeps the caret in the text's color, where it reads as one more
    /// stem among the letters; a color of its own is what sets it apart.
    var caretColor: NSColor?
    var placeholderColor: NSColor = .placeholderTextColor
    var placeholder: String?
    var minimumLines = 8
    var maximumLines = 13
    /// Height the editor holds beyond its minimum lines: what the composer
    /// hands it when a row above is absent, so the card keeps one height
    /// whether or not that row is showing (Perch.previewZoneHeight).
    var extraMinimumHeight: CGFloat = 0
    /// Console editors scroll within the fixed capsule instead of increasing
    /// its height. Other editors retain their content-driven sizing.
    var fitsAvailableHeight = false
    /// When set, the editor takes the keyboard as soon as it is in a window
    /// — for a field that opens on a click elsewhere, so the next thing
    /// typed lands in it.
    var takesFocusOnAppear = false
    /// When set, Return submits instead of breaking the line (Shift-Return
    /// still breaks one) — the chat-composer contract, for the fields whose
    /// text is a message to send rather than prose to shape.
    var onSubmit: (() -> Void)?
    /// When set, Esc reports out instead of invoking NSTextView's word
    /// completion — the way a steer editor gets called off. The text view
    /// comes along so the handler can also just leave focus.
    var onEscape: ((NSTextView) -> Void)?
    var session: TextEditorSession?

    /// The text's inset above and below, inside the editor.
    static let insetHeight: CGFloat = 2

    /// The height the editor settles at for `lines` of `font`, insets
    /// included — for a view that stands in for the editor and must not
    /// move the card when the two swap.
    static func height(lines: Int, font: NSFont) -> CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: font)) * CGFloat(lines) + insetHeight * 2
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = TrailingPlaceholderTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: Self.insetHeight)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        // macOS 27 pins an "Ask Siri" tag to the caret, which is part of
        // Writing Tools and would sit over the console. Opting out of
        // Writing Tools takes it away along with the Writing Tools menu.
        textView.writingToolsBehavior = .none
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = caretColor ?? textColor
        textView.placeholderColor = placeholderColor
        textView.string = text
        textView.trailingPlaceholder = placeholder
        textView.onWidthChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateFont()
        }

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        session?.attach(textView)
        textView.isEditable = context.environment.isEnabled && (session?.acceptsInput ?? true)
        textView.isSelectable = textView.isEditable
        if takesFocusOnAppear {
            // No window yet while the view is being made; by the next turn
            // of the loop it is in one.
            DispatchQueue.main.async {
                guard textView.isEditable, session?.acceptsInput != false else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? TrailingPlaceholderTextView else {
            return
        }
        if textView.textColor != textColor { textView.textColor = textColor }
        let caretColor = caretColor ?? textColor
        if textView.insertionPointColor != caretColor { textView.insertionPointColor = caretColor }
        textView.placeholderColor = placeholderColor
        textView.trailingPlaceholder = placeholder
        // A retained composer is disabled while permission setup covers
        // it. SwiftUI's disabled state must reach AppKit too.
        textView.isEditable = context.environment.isEnabled && (session?.acceptsInput ?? true)
        textView.isSelectable = textView.isEditable
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.updateFont()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView,
                      context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView else { return nil }

        let proposedWidth = proposal.width ?? scrollView.bounds.width
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : scrollView.bounds.width
        let fittedFont = context.coordinator.textLayout.fittedFont(
            for: textView.string, width: width, preferred: font, minimumSize: minimumFontSize)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: fittedFont)
        let insets = textView.textContainerInset.height * 2
        let minimumHeight = Self.height(lines: minimumLines, font: font) + extraMinimumHeight
        let maximumHeight = max(ceil(lineHeight * CGFloat(maximumLines)) + insets, minimumHeight)
        guard width > 0 else {
            return CGSize(width: width, height: minimumHeight)
        }

        // SwiftUI probes several widths during a layout pass. Measuring
        // must not resize the live NSTextView: that relays out its scroll
        // view and invalidates the hosting view's constraints mid-pass.
        let measuredText = NSMutableAttributedString(attributedString: textView.attributedString())
        measuredText.addAttribute(.font, value: fittedFont,
                                  range: NSRange(location: 0, length: measuredText.length))
        let contentHeight = ceil(context.coordinator.textLayout.textHeight(
            measuredText, width: width) + insets)
        var height = min(max(contentHeight, minimumHeight), maximumHeight)
        if fitsAvailableHeight, let available = proposal.height, available.isFinite {
            height = min(height, max(minimumHeight, available))
        }
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var scrollView: NSScrollView?
        let textLayout = PromptTextLayout()

        init(parent: GrowingTextEditor) {
            self.parent = parent
            super.init()
        }

        func updateFont() {
            guard let textView = scrollView?.documentView as? NSTextView,
                  textView.bounds.width > 0, !textView.hasMarkedText() else { return }
            let fittedFont = textLayout.fittedFont(
                for: textView.string, width: textView.bounds.width,
                preferred: parent.font, minimumSize: parent.minimumFontSize)
            if textView.font != fittedFont { textView.font = fittedFont }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? TrailingPlaceholderTextView else {
                return
            }
            // Do not leave the hint painted under the first character while
            // SwiftUI propagates the new binding back through updateNSView.
            textView.trailingPlaceholder = nil
            updateFont()
            parent.text = textView.string
            scrollView?.invalidateIntrinsicContentSize()
            scrollView?.superview?.needsLayout = true
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.window?.firstResponder === textView else { return }
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        func textView(_ textView: NSTextView,
                      doCommandBy commandSelector: Selector) -> Bool {
            // Return/Escape belong to the input method while it is composing.
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               let onSubmit = parent.onSubmit,
               NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
                onSubmit()
                return true
            }
            // Esc reaches an NSTextView as complete: (word completion), or
            // as cancelOperation: when a key-binding layer maps it first;
            // either one is the escape the caller asked to hear about.
            if commandSelector == #selector(NSResponder.cancelOperation(_:))
                || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:)),
               let onEscape = parent.onEscape {
                onEscape(textView)
                return true
            }
            return false
        }
    }
}

/// Draws a hint in NSTextView's extra line fragment — the insertion line
/// after the template body — without adding those characters to its storage.
private final class TrailingPlaceholderTextView: NSTextView {
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    var placeholderColor: NSColor = .placeholderTextColor {
        didSet { needsDisplay = true }
    }
    /// A real NSView inside the panel, so the hosting view's claim on the
    /// first click (FirstMouseHostingView) does not cover it: AppKit asks the
    /// view the click actually hit. Without this, a click into the prompt on
    /// an unfocused console is spent making the panel key and the caret
    /// lands on the second one.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var trailingPlaceholder: String? {
        didSet {
            if trailingPlaceholder != oldValue { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let trailingPlaceholder, !trailingPlaceholder.isEmpty,
              let layoutManager else { return }

        let fragment = layoutManager.extraLineFragmentRect
        let origin = NSPoint(x: textContainerOrigin.x + fragment.minX,
                             y: textContainerOrigin.y + fragment.minY)
        NSAttributedString(
            string: trailingPlaceholder,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: placeholderColor,
            ]
        ).draw(at: origin)
    }
}

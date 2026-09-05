// A multiline prompt editor that follows its content from a useful minimum
// through a bounded maximum, then scrolls. SwiftUI's TextEditor always takes
// the fixed frame it is given; wrapping NSTextView lets the prompt remain a
// real textarea (including Return for paragraph breaks) while participating
// in the panel's layout.

import AppKit
import SwiftUI

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor = .labelColor
    var placeholder: String?
    var minimumLines = 8
    var maximumLines = 13
    /// Height the editor holds beyond its minimum lines: what the composer
    /// hands it when a row above is absent, so the card keeps one height
    /// whether or not that row is showing (Perch.previewZoneHeight).
    var extraMinimumHeight: CGFloat = 0
    /// When set, Return submits instead of breaking the line (Shift-Return
    /// still breaks one) — the chat-composer contract, for the fields whose
    /// text is a message to send rather than prose to shape.
    var onSubmit: (() -> Void)?
    /// When set, Esc reports out instead of invoking NSTextView's word
    /// completion — the way a steer editor gets called off. The text view
    /// comes along so the handler can also just leave focus.
    var onEscape: ((NSTextView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = TrailingPlaceholderTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        textView.trailingPlaceholder = placeholder

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? TrailingPlaceholderTextView else {
            return
        }
        textView.font = font
        textView.textColor = textColor
        textView.trailingPlaceholder = placeholder
        if textView.string != text {
            textView.string = text
        }
        scrollView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView,
                      context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return nil }

        let width = proposal.width ?? scrollView.frame.width
        guard width > 0 else {
            return CGSize(width: width,
                          height: lineHeight * CGFloat(minimumLines) + extraMinimumHeight)
        }

        textView.frame.size.width = width
        textContainer.containerSize = NSSize(width: width,
                                             height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let insets = textView.textContainerInset.height * 2
        let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height + insets)
        let minimumHeight = lineHeight * CGFloat(minimumLines) + insets + extraMinimumHeight
        let maximumHeight = max(lineHeight * CGFloat(maximumLines) + insets, minimumHeight)
        let height = min(max(contentHeight, minimumHeight), maximumHeight)
        return CGSize(width: width, height: height)
    }

    private var lineHeight: CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: font))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var scrollView: NSScrollView?

        init(parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? TrailingPlaceholderTextView else {
                return
            }
            // Do not leave the hint painted under the first character while
            // SwiftUI propagates the new binding back through updateNSView.
            textView.trailingPlaceholder = nil
            parent.text = textView.string
            scrollView?.invalidateIntrinsicContentSize()
            scrollView?.superview?.needsLayout = true
        }

        func textView(_ textView: NSTextView,
                      doCommandBy commandSelector: Selector) -> Bool {
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
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        ).draw(at: origin)
    }
}

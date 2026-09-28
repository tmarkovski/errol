import AppKit

/// A separate TextKit stack keeps measurement out of the live editor's layout.
/// Short drafts keep their display size; longer drafts shrink before wrapping.
final class PromptTextLayout {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(
        containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    // The fit is cached per width because GrowingTextEditor measures the same
    // draft at two: sizeThatFits gets SwiftUI's unrounded proposal (582.8)
    // and the coordinator's updateFont the pixel-rounded bounds (583.0). A
    // single entry alternated between them and missed twice per keystroke.
    private var fitKey: (text: String, preferred: NSFont, minimum: CGFloat)?
    private var fitsByWidth: [CGFloat: NSFont] = [:]

    init() {
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }

    func fittedFont(for text: String, width: CGFloat, preferred: NSFont,
                    minimumSize: CGFloat?) -> NSFont {
        guard let minimumSize, !text.isEmpty, width > 0, width.isFinite else {
            return preferred
        }
        let minimum = min(preferred.pointSize, max(1, minimumSize))
        if let fitKey, fitKey.text == text, fitKey.preferred == preferred,
           fitKey.minimum == minimum {
            if let cached = fitsByWidth[width] { return cached }
        } else {
            fitsByWidth.removeAll()
            fitKey = (text, preferred, minimum)
        }

        func font(at size: CGFloat) -> NSFont {
            NSFontManager.shared.convert(preferred, toSize: size)
        }
        func fits(_ font: NSFont) -> Bool {
            // Measuring without a wrapping width uses the longest paragraph,
            // including fallback glyphs for emoji and non-Latin scripts.
            (text as NSString).size(withAttributes: [.font: font]).width <= width
        }

        let result: NSFont
        if fits(preferred) {
            result = preferred
        } else if !fits(font(at: minimum)) {
            result = font(at: minimum)
        } else {
            var lower = minimum
            var upper = preferred.pointSize
            // Real font metrics vary with size; a width ratio alone can wrap
            // early. Find the largest size that actually fits the paragraph.
            while upper - lower > 0.05 {
                let middle = (lower + upper) / 2
                if fits(font(at: middle)) { lower = middle }
                else { upper = middle }
            }
            result = font(at: lower)
        }
        // SwiftUI probes a few more widths during a layout pass; four
        // entries hold them without letting a resize drag grow the cache.
        if fitsByWidth.count >= 4 { fitsByWidth.removeAll() }
        fitsByWidth[width] = result
        return result
    }

    func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        if !storage.isEqual(to: text) { storage.setAttributedString(text) }
        if container.containerSize.width != width { container.containerSize.width = width }
        layout.ensureLayout(for: container)
        // A trailing Return creates an empty insertion line. usedRect alone
        // misses it, leaving the caret clipped until another character arrives.
        return max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
    }
}

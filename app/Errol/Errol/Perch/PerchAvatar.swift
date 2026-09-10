// The perch avatar: the app's own icon, as installed on this Mac, with the
// initial in a feather-colored circle standing in when the app is not here.
//
// Why the installed icon rather than a bundled logo. Both vendors gate their
// marks: OpenAI's Blossom may only appear black or white, under its Marks
// usage terms, and Anthropic's trademark guidelines allow its marks only in
// materials Anthropic approves beforehand — so a Claude starburst shipped
// inside Errol would need written permission. Showing an installed app's
// icon is what the Dock, Finder, and the app switcher do for every app:
// nothing of either brand lives in this bundle, and the avatar follows
// whichever app the bundle ID in Settings names (Codex or classic ChatGPT
// alike), which the initial could not.

import AppKit
import SwiftUI

struct PerchAvatar: View {
    let bundleID: String
    /// The fallback's letter — the app name's first character.
    let initial: String
    /// The fallback circle's fill (Perch.chatgptFeather / claudeFeather).
    let feather: Color
    let presence: Color
    /// A check in place of the dot: the side is connected and ready.
    var check = false

    /// The layout slot: the same for the icon and the fallback so the head
    /// does not shift depending on which apps are installed.
    private var slot: CGFloat { Perch.s(46) }

    var body: some View {
        Group {
            if let icon = AppIcons.icon(forBundleID: bundleID) {
                // A macOS app icon keeps a transparent margin around its
                // squircle — the squircle spans about 81% of the canvas
                // (measured on both apps' icons) — so the image is drawn
                // oversize inside the slot to make the squircle itself
                // slot-sized, matching the fallback circle. The overflow is
                // only that margin; nothing paints outside the slot.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: slot / 0.81, height: slot / 0.81)
                    .frame(width: slot, height: slot)
            } else {
                ZStack {
                    Circle()
                        .fill(feather)
                        .frame(width: slot, height: slot)
                    Text(initial)
                        .font(Perch.text(17, .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(presence)
                    .frame(width: Perch.s(check ? 14 : 11), height: Perch.s(check ? 14 : 11))
                    .overlay(Circle().stroke(Perch.paper, lineWidth: Perch.s(2)))
                if check {
                    Image(systemName: "checkmark")
                        .font(.system(size: Perch.s(7), weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .offset(x: Perch.s(1), y: Perch.s(1))
        }
    }
}

/// Icons of the apps the relay targets, looked up by bundle ID through
/// LaunchServices so an app that is installed but not running still has a
/// face. Hits are cached for the process; misses are not, so installing an
/// app while Errol runs shows its icon on the next head refresh.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    private static var markCache: [String: NSImage] = [:]

    /// Where each app keeps a flat rendition of its own mark, best first.
    /// The catalog assets are the sharp ones: Claude's spark is a PDF vector,
    /// ChatGPT Classic's menu-bar Blossom an SVG, and the ChatGPT (Codex)
    /// app's layered icon carries a 1024 px Blossom layer — the dark one,
    /// whose alpha is the bare silhouette; the light layer bakes a shadow into
    /// its alpha. The loose menu-bar PNGs (36 px and 72 px) stay as fallbacks.
    /// Names are optional: a vendor update or custom target falls back to its
    /// LaunchServices icon, never another app's identity.
    private enum MarkSource {
        /// A named asset in the app's catalog: a vector or a bitmap.
        case asset(String)
        /// A loose file in the app's Resources folder.
        case file(String)
    }

    private static func markSources(for bundleID: String) -> [MarkSource] {
        switch bundleID {
        case "com.openai.codex":
            return [.asset("Icon_Assets/Blossom dark"),
                    .file("chatgptTemplate@2x.png"), .file("chatgptTemplate.png")]
        case "com.openai.chat":
            return [.asset("MenuBarIcon"),
                    .file("chatgptTemplate@2x.png"), .file("chatgptTemplate.png")]
        case "com.anthropic.claudefordesktop":
            return [.asset("ClaudeSpark"), .file("TrayIconTemplate@3x.png"),
                    .file("TrayIconTemplate@2x.png"), .file("TrayIconTemplate.png")]
        default:
            return []
        }
    }

    /// The installed app's own mark as a template image, or nil when the app
    /// is missing or keeps no flat rendition Errol knows the name of.
    @MainActor
    static func mark(forBundleID bundleID: String) -> NSImage? {
        if let hit = markCache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        for source in markSources(for: bundleID) {
            let image: NSImage?
            switch source {
            case .asset(let name):
                image = bundle.image(forResource: name)
            case .file(let name):
                image = bundle.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent(name)) }
            }
            if let image, let mark = flatMark(of: image) {
                markCache[bundleID] = mark
                return mark
            }
        }
        return nil
    }

    /// The side, in pixels, of a finished mark: the head draws marks at 40 pt,
    /// so this stays crisp on a 3x display while keeping the cache small.
    private static let markSide = 256

    /// Reduces any rendition of a mark — a vector, a 1024 px icon layer, a
    /// menu-bar PNG — to one shape: a black-on-clear template whose artwork
    /// spans the whole square. Cropping to the artwork is what makes the two
    /// apps' marks share a size in the head, since each vendor pads its canvas
    /// differently (the Claude tray PNG leaves a third of it empty, the
    /// Blossom layer a fifth); painting the alpha black is what keeps the icon
    /// layer's gloss, and any vendor color, off the screen.
    private static func flatMark(of image: NSImage) -> NSImage? {
        let canvas = image.size
        guard canvas.width > 0, canvas.height > 0, let fitted = bitmap(side: markSide * 2) else { return nil }
        // Pass 1: the artwork drawn to fit, inset so its crop never leaves the
        // bitmap, with only its alpha kept.
        draw(into: fitted) { rect in
            let inset = rect.insetBy(dx: rect.width / 8, dy: rect.height / 8)
            let scale = min(inset.width / canvas.width, inset.height / canvas.height)
            let size = NSSize(width: canvas.width * scale, height: canvas.height * scale)
            image.draw(in: NSRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2,
                                  width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.black.set()
            rect.fill(using: .sourceIn)
        }
        guard let content = opaqueBounds(of: fitted), let finished = bitmap(side: markSide) else { return nil }
        // Pass 2: the square around the artwork, scaled to fill the mark.
        let span = max(content.width, content.height)
        let crop = NSRect(x: content.midX - span / 2, y: content.midY - span / 2, width: span, height: span)
            .intersection(NSRect(origin: .zero, size: fitted.size))
        let source = NSImage(size: fitted.size)
        source.addRepresentation(fitted)
        draw(into: finished) { rect in
            source.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1)
        }
        let mark = NSImage(size: finished.size)
        mark.addRepresentation(finished)
        mark.isTemplate = true
        return mark
    }

    private static func bitmap(side: Int) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = NSSize(width: side, height: side)
        return rep
    }

    /// Runs `body` with `rep` as the current drawing destination; the rect is
    /// its full extent, one point per pixel.
    private static func draw(into rep: NSBitmapImageRep, _ body: (NSRect) -> Void) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        body(NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The rectangle, in drawing coordinates, of the pixels at least half
    /// covered — the artwork, without anti-aliasing fringe or a soft shadow.
    /// Nil when nothing is drawn.
    private static func opaqueBounds(of rep: NSBitmapImageRep) -> NSRect? {
        guard let data = rep.bitmapData else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        let rowBytes = rep.bytesPerRow, samples = rep.samplesPerPixel
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            for column in 0..<width where data[row * rowBytes + column * samples + 3] >= 128 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Rows run top-down in memory and bottom-up in drawing coordinates.
        return NSRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @MainActor
    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

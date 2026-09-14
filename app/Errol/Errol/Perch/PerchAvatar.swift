// The perch avatar: the app's own icon, as installed on this Mac, with the
// initial in a feather-colored circle standing in when the app is not here.
//
// Artwork stays in the installed app's bundle. ChatGPT's optional Codex
// artwork follows its Dock preference; other apps use their macOS icon.

import AppKit
import Combine
import Observation
import SwiftUI

struct PerchAvatar: View {
    let bundleID: String
    /// The fallback's letter — the app name's first character.
    let initial: String
    /// The fallback circle's fill (Perch.chatgptFeather / claudeFeather).
    let feather: Color
    /// The mark in the corner: how the side's connection reads. Nil before
    /// the side is connected, when the corner stays bare.
    var presence: Color? = nil
    /// A check in place of the dot: the side is connected and ready.
    var check = false

    /// The layout slot: the same for the icon and the fallback so the head
    /// does not shift depending on which apps are installed.
    private var slot: CGFloat { Perch.s(46) }

    var body: some View {
        Group {
            if let icon = AppIcons.shared.icon(forBundleID: bundleID) {
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
            if let presence {
                ZStack {
                    Circle()
                        .fill(presence)
                        .frame(width: Perch.s(check ? 18 : 11), height: Perch.s(check ? 18 : 11))
                        .overlay(Circle().stroke(Perch.paper, lineWidth: Perch.s(2)))
                    if check {
                        Image(systemName: "checkmark")
                            .font(.system(size: Perch.s(9), weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: Perch.s(1), y: Perch.s(1))
            }
        }
    }
}

/// Icons of the apps the relay targets, looked up by bundle ID through
/// LaunchServices so an app that is installed but not running still has a
/// face. Changes to the installed apps, Dock preference, or system appearance
/// invalidate the cache and redraw existing avatars without restarting setup.
@MainActor
@Observable
final class AppIcons {
    static let shared = AppIcons()

    private var revision = 0
    @ObservationIgnored private var cache: [String: NSImage] = [:]
    @ObservationIgnored private var subscriptions: [AnyCancellable] = []
    private static var markCache: [String: NSImage] = [:]

    private init() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let notifications = [
            distributed.publisher(for: Notification.Name("com.openai.codex.DockIconPreferenceChanged")),
            distributed.publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification")),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification),
        ]
        for publisher in notifications {
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in
                self?.cache.removeAll()
                Self.markCache.removeAll()
                self?.revision &+= 1
            }.store(in: &subscriptions)
        }
    }

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
    func icon(forBundleID bundleID: String) -> NSImage? {
        // Register an observation even on a cache hit. The cache itself is
        // ignored so loading an image during rendering does not publish.
        _ = revision
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = Self.selectedDockIcon(bundleID: bundleID, appURL: url)
            ?? NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }

    /// ChatGPT's Dock plug-in changes its tile without changing the Finder
    /// icon. These optional vendor keys are read only; an unknown preference
    /// or missing asset falls back to the ordinary installed icon above.
    private static func selectedDockIcon(bundleID: String, appURL: URL) -> NSImage? {
        guard bundleID == "com.openai.codex" else { return nil }
        CFPreferencesAppSynchronize(bundleID as CFString)
        let preference = CFPreferencesCopyAppValue("DockIconPreference" as CFString,
                                                   bundleID as CFString) as? String
        let resourceName = CFPreferencesCopyAppValue("DockIconResourceName" as CFString,
                                                     bundleID as CFString) as? String
        // Match the Dock's system appearance, independently of Errol's theme.
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        guard let filename = codexIconResource(preference: preference, resourceName: resourceName,
                                              dark: dark),
              let resources = Bundle(url: appURL)?.resourceURL else { return nil }
        return NSImage(contentsOf: resources.appendingPathComponent(filename))
    }

    /// Keep this mapping separate from preference I/O so fallback and light/
    /// dark selection can be checked without changing another app's settings.
    static func codexIconResource(preference: String?, resourceName: String?, dark: Bool) -> String? {
        let useDark: Bool
        switch preference {
        case "codex-system": useDark = dark
        case "codex-light": useDark = false
        case "codex-dark": useDark = true
        default: return nil
        }
        let light = resourceName ?? "icon-codex-light.png"
        // Only accept a file in this bundle's Resources folder. Keep optional
        // build-flavor suffixes while following the vendor's paired filenames.
        guard light.hasPrefix("icon-codex-light"), light.hasSuffix(".png"),
              !light.contains("/"), !light.contains("\\"), !light.contains("..") else { return nil }
        return useDark
            ? "icon-codex-dark-color" + light.dropFirst("icon-codex-light".count)
            : light
    }
}

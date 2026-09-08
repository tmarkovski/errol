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
            Circle()
                .fill(presence)
                .frame(width: Perch.s(11), height: Perch.s(11))
                .overlay(Circle().stroke(Perch.paper, lineWidth: Perch.s(2)))
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

    /// Prefer the installed app's own transparent menu-bar mark. Resource
    /// names are optional: a vendor update or custom target falls back to
    /// its LaunchServices icon, never another app's identity.
    @MainActor
    static func mark(forBundleID bundleID: String) -> NSImage? {
        if let hit = markCache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let resources = Bundle(url: url)?.resourceURL else { return nil }
        let names: [String]
        switch bundleID {
        case "com.openai.chat", "com.openai.codex":
            names = ["chatgptTemplate@2x.png", "chatgptTemplate.png"]
        case "com.anthropic.claudefordesktop":
            names = ["TrayIconTemplate@3x.png", "TrayIconTemplate@2x.png", "TrayIconTemplate.png"]
        default: return nil
        }
        for name in names {
            if let image = NSImage(contentsOf: resources.appendingPathComponent(name)) {
                image.isTemplate = true
                markCache[bundleID] = image
                return image
            }
        }
        return nil
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

struct PerchWidgetParticipant: View {
    let controller: RelayController
    let speaker: Speaker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: SideStatus {
        speaker == .chatgpt ? controller.chatgptStatus : controller.claudeStatus
    }
    private var conversation: ConversationStatus {
        speaker == .chatgpt ? controller.chatgptConversation : controller.claudeConversation
    }
    private var bundleID: String {
        speaker == .chatgpt ? config.chatgptBundleID : config.claudeBundleID
    }
    private var active: Bool { controller.isRunning && conversation == .chatting }
    private var chosen: Bool {
        !controller.isRunning && !controller.hasFinishedRun && controller.firstSpeaker == speaker
    }
    private var markColor: Color { speaker == .claude ? Perch.claudeFeather : Perch.ink }
    private var presence: Color {
        switch status.state {
        case .ready: return Perch.presence
        case .checking: return Perch.path
        case .notReady, .missing: return Perch.red
        }
    }

    var body: some View {
        Button {
            guard !controller.isRunning, !controller.hasFinishedRun else { return }
            controller.firstSpeaker = speaker
        } label: {
            VStack(spacing: Perch.s(9)) {
                Group {
                    if let mark = AppIcons.mark(forBundleID: bundleID) {
                        Image(nsImage: mark).resizable().renderingMode(.template)
                            .interpolation(.high).scaledToFit().foregroundStyle(markColor)
                    } else if let icon = AppIcons.icon(forBundleID: bundleID) {
                        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Text(String(status.appName.prefix(1)))
                            .font(Perch.text(30, .medium)).foregroundStyle(markColor)
                    }
                }
                .frame(width: Perch.s(40), height: Perch.s(40))
                .opacity(controller.isRunning && !active ? 0.6 : 1)
                Group {
                    if active {
                        TimelineView(.animation(minimumInterval: 0.3, paused: reduceMotion)) { context in
                            HStack(spacing: Perch.s(3)) {
                                ForEach(0..<3) { index in
                                    Circle().fill(markColor)
                                        .opacity(reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 3) % 3 == index ? 1 : 0.3)
                                        .frame(width: Perch.s(4), height: Perch.s(4))
                                }
                            }
                        }
                    } else if chosen {
                        Capsule().fill(presence).frame(width: Perch.s(18), height: Perch.s(3))
                    } else {
                        Circle().fill(presence).frame(width: Perch.s(5), height: Perch.s(5))
                    }
                }
                .frame(height: Perch.s(5))
            }
            .frame(width: Perch.s(56))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(details)
        .accessibilityLabel(status.appName)
        .accessibilityValue(details)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var details: String {
        var parts = [status.headline]
        if let surface = status.surface { parts.append(surface) }
        if let model = status.model { parts.append(model) }
        if active { parts.append("Replying") }
        else if chosen { parts.append("Starts the conversation") }
        else if !controller.isRunning && !controller.hasFinishedRun { parts.append("Click to start with \(status.appName)") }
        if let detail = status.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}

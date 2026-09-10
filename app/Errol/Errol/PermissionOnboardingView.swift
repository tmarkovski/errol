// Permission setup takes the console's own capsule: the same low, wide row,
// with the request at the leading end where an app's mark would sit, the
// explanation in the center, and the one action at the trailing end where
// Run sits. The shell polls macOS and crossfades the console back in as soon
// as access is granted. The first click registers Errol with the system
// prompt; later clicks open its settings pane.

import ApplicationServices
import SwiftUI

struct PermissionOnboardingView: View {
    private static let didPromptKey = "didRequestAXPermission"
    var width: CGFloat = Perch.widgetWidth

    var body: some View {
        HStack(spacing: Perch.s(18)) {
            badge
            Rectangle().fill(Perch.hairline)
                .frame(width: 1, height: Perch.s(58))
            explanation
                .layoutPriority(1)
            action
        }
        .padding(.horizontal, Perch.s(24))
        .padding(.vertical, Perch.s(22))
        .frame(width: width)
        .frame(minHeight: Perch.widgetHeight)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Perch.accent)
        .background(Perch.paper.gesture(WindowDragGesture()))
        .clipShape(Capsule())
    }

    /// The leading end, in the participants' slot: the permission glyph in
    /// an accent well, over the red presence dot a participant shows while
    /// it is not ready. Until the grant, neither side can be.
    private var badge: some View {
        VStack(spacing: Perch.s(7)) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: Perch.s(22), weight: .medium))
                .foregroundStyle(Perch.accentText)
                .frame(width: Perch.s(44), height: Perch.s(44))
                .background(Circle().fill(Perch.accentBack))
            Circle().fill(Perch.red)
                .frame(width: Perch.s(5), height: Perch.s(5))
        }
        .frame(width: Perch.s(56))
        .accessibilityHidden(true)
    }

    /// The center, where the prompt sits on the console: what is asked, why,
    /// and where to do it. The last line is the whole path, so nobody has to
    /// find Accessibility inside System Settings on their own. Each line fits
    /// the full-width console on one line, keeping this row the console's
    /// height so the crossfade into it moves nothing; a narrower screen wraps
    /// and grows the capsule instead of truncating an instruction.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: Perch.s(5)) {
            Text("Allow Accessibility access")
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(2)
            Text("Errol needs it to read replies and send messages between your two desktop apps.")
                .font(Perch.text(12))
                .foregroundStyle(Perch.secondary)
                .lineLimit(3)
            Text("System Settings › Privacy & Security › Accessibility, then turn on Errol.")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .lineLimit(3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The trailing end, where Run sits: the one action, filled like Run and
    /// labeled because a first-time user has nothing to guess an icon from.
    /// The line beneath says the shell is polling, so nobody relaunches.
    private var action: some View {
        VStack(alignment: .trailing, spacing: Perch.s(7)) {
            Button(action: requestAccess) {
                Text("Open Accessibility Settings…")
                    .font(Perch.text(13, .semibold))
                    .foregroundStyle(Perch.onAccent)
                    .padding(.horizontal, Perch.s(18))
                    .frame(height: Perch.s(42))
                    .background(Capsule().fill(Perch.accent))
                    .perchHover(Capsule(), tint: .white)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            Label("Clears on its own once access is ready", systemImage: "lock")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
        }
        .fixedSize()
    }

    private func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let alreadyPrompted = UserDefaults.standard.bool(forKey: Self.didPromptKey)
        guard !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else { return }
        UserDefaults.standard.set(true, forKey: Self.didPromptKey)
        if alreadyPrompted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if DEBUG
#Preview("Permission setup") {
    PermissionOnboardingView()
}
#endif

// Permission setup takes the console's own capsule: the same low, wide row,
// with the request at the leading end where an app's mark would sit, the
// explanation in the center, and the one action at the trailing end where
// Run sits. The shell polls macOS and crossfades the console back in as soon
// as access is granted. The action opens the list in System Settings with
// a guide docked under its window, holding Errol's icon to drag into the
// list (PermissionGuide).

import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct PermissionOnboardingView: View {
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
        .frame(width: width, height: Perch.widgetHeight)
        .tint(Perch.accent)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .clipShape(Capsule())
    }

    /// The leading end, in the participants' slot: the icon System Settings
    /// shows beside the list, at the size of the apps' icons on the console,
    /// so the tile here is the one to look for in Privacy & Security. macOS
    /// draws it from the list's own type and so keeps it current. Where the
    /// system doesn't declare that type, the list's symbol stands on a blue
    /// tile of the same shape.
    private var badge: some View {
        let slot = PerchAvatar.slot
        return Group {
            if let icon = Self.listIcon {
                // Like an app icon, the tile spans 81% of the image.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: slot / 0.81, height: slot / 0.81)
                    .frame(width: slot, height: slot)
            } else {
                Image(systemName: AccessPermission.isRenamed ? "folder.badge.gearshape" : "accessibility")
                    .font(.system(size: slot * 0.45, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: slot, height: slot)
                    .background(RoundedRectangle(cornerRadius: slot * 0.225, style: .continuous)
                        .fill(Color(nsColor: .systemBlue)))
            }
        }
        .frame(width: Perch.s(56))
        .accessibilityHidden(true)
    }

    /// The list's icon as System Settings draws it, looked up once.
    private static let listIcon: NSImage? = {
        guard let type = UTType("com.apple.settings.PrivacySecurity.extension.privacy-accessibility"),
              type.isDeclared else { return nil }
        return NSWorkspace.shared.icon(for: type)
    }()

    /// The center, where the prompt sits on the console: what is asked,
    /// why, and where to do it. The headline and the path use the list's
    /// name on this system, the one macOS shows in its prompt and in
    /// System Settings, so nobody has to hunt for it. Supporting text wraps
    /// within the same fixed capsule.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: Perch.s(5)) {
            Text(AccessPermission.isRenamed ? "Enable Device Control and Data Access" : "Enable Accessibility access")
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(2)
            Text("Errol needs it to read replies and send messages between your two desktop apps.")
                .font(Perch.text(12))
                .foregroundStyle(Perch.secondary)
                .lineLimit(3)
            Text("\(AccessPermission.settingsPath). Add Errol and turn it on.")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .lineLimit(3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The trailing end, where Run sits: the one action in the console's own
    /// capsule, labeled like its other actions because a first-time user
    /// has nothing to guess an icon from, and the note beneath it saying
    /// the shell is polling, so nobody relaunches. The two stand together,
    /// centered on the row.
    private var action: some View {
        VStack(alignment: .trailing, spacing: Perch.s(7)) {
            PerchCapsuleButton(title: "Open System Settings", icon: "arrow.up.right", action: requestAccess)
                .keyboardShortcut(.defaultAction)
            Label("Checks access automatically", systemImage: "lock")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
        }
        .fixedSize()
    }

    /// Opens the list with the guide under System Settings. The system
    /// prompt this replaces put up a dialog of its own and then left Errol
    /// in the list switched off; dropping Errol into the list allows it.
    private func requestAccess() {
        guard !AXIsProcessTrusted() else { return }
        PermissionGuide.show()
    }
}

#if DEBUG
#Preview("Permission setup") {
    PermissionOnboardingView()
}
#endif

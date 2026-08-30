// The pre-permission explainer shown at launch while the Accessibility
// grant is missing. Standard priming pattern: say what will be requested
// and why before the system dialog appears, offer the request as an
// explicit choice, and keep watching so the screen acknowledges the grant
// the moment it lands (the user is off in System Settings when it does).
//
// The first Grant click goes through AXIsProcessTrustedWithOptions so macOS
// shows its own dialog and registers Errol in the Accessibility list; once
// that dialog has been spent (the API only ever shows it once), later
// clicks deep-link straight to the pane instead of silently doing nothing.

import ApplicationServices
import Combine
import SwiftUI

struct PermissionOnboardingView: View {
    /// Close the window and open the panel — the "granted, get started" path.
    let onFinished: () -> Void
    /// Close the window without the grant; Start still re-asks later.
    let onDismiss: () -> Void

    @State private var trusted = AXIsProcessTrusted()
    private let poll = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()
    private static let didPromptKey = "didRequestAXPermission"

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Errol needs Accessibility access")
                .font(.title2.bold())
            Text("Errol relays a conversation between the ChatGPT and Claude "
                 + "desktop apps. macOS only lets it read and press another "
                 + "app's controls through the Accessibility permission, so "
                 + "nothing works until it is granted.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                row(icon: "text.magnifyingglass",
                    title: "Reads the two chat windows",
                    detail: "Finds each app's message box and copies finished "
                        + "replies out — that is how a reply crosses over.")
                row(icon: "keyboard",
                    title: "Types and sends on your behalf",
                    detail: "Pastes each reply into the other app and presses "
                        + "its own Send button, one turn at a time.")
                row(icon: "lock",
                    title: "Stays on your Mac",
                    detail: "Only ChatGPT and Claude are driven, nothing else "
                        + "is read, and the transcript is saved to your "
                        + "Documents folder.")
            }
            .padding(.vertical, 18)

            if trusted {
                Label("Accessibility access is granted", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Start Using Errol") { onFinished() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Button("Grant Accessibility Access…") { requestAccess() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                Text("macOS will ask you to allow Errol under "
                     + "Privacy & Security › Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Not Now") { onDismiss() }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
        }
        .padding(28)
        .frame(width: 440)
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let alreadyPrompted = UserDefaults.standard.bool(forKey: Self.didPromptKey)
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            trusted = true
            return
        }
        UserDefaults.standard.set(true, forKey: Self.didPromptKey)
        // The system dialog is one-shot per TCC entry; once it has been
        // used up, take the user to the pane itself.
        if alreadyPrompted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

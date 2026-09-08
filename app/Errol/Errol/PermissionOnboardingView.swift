// Permission setup is a blocking card over the blurred console. The shell
// polls macOS and removes it as soon as access is granted. The first click
// registers Errol with the system prompt; later clicks open its settings pane.

import ApplicationServices
import SwiftUI

struct PermissionOnboardingView: View {
    private static let didPromptKey = "didRequestAXPermission"

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(18)) {
            HStack(spacing: Perch.s(12)) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: Perch.s(24), weight: .medium))
                    .foregroundStyle(Perch.accentText)
                    .frame(width: Perch.s(48), height: Perch.s(48))
                    .background(RoundedRectangle(cornerRadius: Perch.s(12))
                        .fill(Perch.accentBack))
                VStack(alignment: .leading, spacing: Perch.s(4)) {
                    Text("Allow Accessibility access")
                        .font(Perch.text(18, .semibold))
                        .foregroundStyle(Perch.ink)
                    Text("One step before your first conversation.")
                        .font(Perch.text(12))
                        .foregroundStyle(Perch.secondary)
                }
            }

            Text("Errol needs permission to read replies and send messages between your two desktop apps.")
                .font(Perch.text(13))
                .foregroundStyle(Perch.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Perch.s(14)) {
                step("1", "Open Accessibility in System Settings.")
                step("2", "Turn on the switch next to Errol.")
                step("3", "Come back here. This screen clears automatically when access is ready.")
            }

            Button(action: requestAccess) {
                Text("Open Accessibility Settings…")
                    .font(Perch.text(13, .semibold))
                    .foregroundStyle(Perch.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Perch.s(11))
                    .background(RoundedRectangle(cornerRadius: Perch.s(9)).fill(Perch.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            Label("Waiting for Accessibility access", systemImage: "lock")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(Perch.s(22))
        .background(RoundedRectangle(cornerRadius: Perch.s(16)).fill(Perch.paper))
        .overlay(RoundedRectangle(cornerRadius: Perch.s(16))
            .stroke(Perch.chipEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(10)) {
            Text(number)
                .font(Perch.text(12, .semibold))
                .foregroundStyle(Perch.accentText)
                .frame(width: Perch.s(22))
            Text(text)
                .font(Perch.text(12))
                .foregroundStyle(Perch.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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

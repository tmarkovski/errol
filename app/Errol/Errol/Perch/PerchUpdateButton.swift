// The update, beside the ··· menu at the top row's trailing end: a small
// capsule of accent glass while a new version is on offer, which a click
// installs by relaunching into it (UpdaterController). While it downloads
// and while Errol restarts, the capsule stays and says so. After a check
// the user asked for turns up nothing, a muted note stands in its place
// for a few seconds. A run hides all of it: nothing about an update may
// happen until the run is over.

import SwiftUI

extension EnvironmentValues {
    /// The app's one update status, which the canvases replace with
    /// stand-ins (UpdateStatus.preview).
    @Entry var updateStatus: UpdateStatus = .shared
}

struct PerchUpdateButton: View {
    /// A run is live.
    let hidden: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.updateStatus) private var status

    var body: some View {
        Group {
            if !hidden {
                if let version = status.version {
                    capsule(version: version)
                } else if status.phase == .restarting {
                    capsule(version: nil)
                } else if status.phase == .checking {
                    note("Checking\u{2026}", symbol: nil, help: "Checking for updates")
                } else if let current = status.note {
                    switch current {
                    case .upToDate:
                        note("Errol is up to date", symbol: "checkmark", help: nil)
                    case .problem(let message):
                        note("Couldn\u{2019}t update", symbol: "exclamationmark.triangle", help: message)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
        .animation(Perch.fade, value: status.phase)
        .animation(Perch.fade, value: status.note)
    }

    private var busy: Bool {
        switch status.phase {
        case .preparing, .restarting: true
        default: false
        }
    }

    private var title: String {
        switch status.phase {
        case .preparing: "Updating\u{2026}"
        case .restarting: "Restarting\u{2026}"
        default: "Update"
        }
    }

    private func help(version: String?) -> String {
        guard let version else { return "Errol is restarting into the new version" }
        switch status.phase {
        case .available: return "Download Errol \(version) and restart into it"
        case .ready: return "Restart into Errol \(version). It also installs the next time Errol quits"
        default: return "Downloading Errol \(version); Errol restarts when it\u{2019}s ready"
        }
    }

    private func capsule(version: String?) -> some View {
        Button { status.update() } label: {
            HStack(spacing: Perch.s(4)) {
                // One plain arrow throughout; while busy it keeps
                // bouncing upward.
                Image(systemName: "arrow.up")
                    .font(Perch.text(10, .semibold))
                    .symbolEffect(.bounce.up, options: .repeat(.continuous), isActive: busy && !reduceMotion)
                Text(title)
                    .font(Perch.text(11.5, .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Perch.onAccent)
            .lineLimit(1)
            .padding(.horizontal, Perch.s(8))
            .frame(height: PerchChip.height)
            .perchGlass(prominent: true, in: Capsule())
            .perchHover(Capsule(), tint: .white, opacity: busy ? 0 : 0.12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!busy)
        .fixedSize()
        .help(help(version: version))
        .accessibilityLabel(busy ? title : "Update Errol")
        .accessibilityHint(help(version: version))
    }

    private func note(_ text: String, symbol: String?, help: String?) -> some View {
        HStack(spacing: Perch.s(4)) {
            // Set in text: as an image inside the console, symbols came out
            // white in the offscreen renders (PerchChipLabel).
            if let symbol { Text(Image(systemName: symbol)).font(Perch.text(9.5, .semibold)) }
            Text(text)
        }
        .font(Perch.text(11.5))
        .foregroundStyle(Perch.muted)
        .lineLimit(1)
        .fixedSize()
        .help(help ?? text)
        .accessibilityElement(children: .combine)
    }
}

// The run log in a debug window of its own: the log is kept in memory
// (RelayController.logLines) and read through the owl menu's "Show Last Run
// Log" — Inspect reports land here too. Dressed like the settings card: the
// panel's paper, the log in a well.

import SwiftUI

/// The debug window's content, filling whatever size the resizable window
/// is dragged to. The top padding clears the bare title strip the close
/// button stands in (28pt — no toolbar here, unlike the console's unified
/// bar).
struct PerchLogWindowView: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            Text("Last run log")
                .font(Perch.text(11, .medium))
                .foregroundColor(Perch.muted)
            logWell
        }
        .padding(.horizontal, Perch.s(16))
        .padding(.bottom, Perch.s(16))
        .padding(.top, 28 + Perch.s(6))
        .frame(minWidth: Perch.s(380), maxWidth: .infinity,
               minHeight: Perch.s(220), maxHeight: .infinity)
        .background(Perch.paper)
        .environment(\.colorScheme, .light)
    }

    /// The scrolling tail of the log, following the newest line.
    private var logWell: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Perch.s(2)) {
                    if controller.logLines.isEmpty {
                        Text("No run yet — the log fills as one goes.")
                            .font(Perch.mono(10.5))
                            .foregroundColor(Perch.muted)
                    }
                    ForEach(controller.logLines) { line in
                        Text(line.text)
                            .font(Perch.mono(10.5))
                            .foregroundColor(Perch.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Perch.s(10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Perch.bandCorner).fill(Perch.well))
            .overlay(RoundedRectangle(cornerRadius: Perch.bandCorner)
                .stroke(Perch.chipEdge, lineWidth: 1))
            .onChange(of: controller.logLines.count) { _, _ in
                if let last = controller.logLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview("Log window") {
    let controller = RelayController()
    controller.append("Run starting. Transcript: ~/errol-transcript.md")
    controller.append("Turn 1 · ChatGPT is replying")
    controller.append("Turn 2 · Claude is replying")
    controller.append("Pause requested — the run holds at the next handoff.")
    return PerchLogWindowView(controller: controller)
        .frame(width: 560, height: 420)
}

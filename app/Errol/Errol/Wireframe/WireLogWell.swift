// The log well, moved off the console into its own debug window: the run
// log is kept in memory (RelayController.logLines) and read through the
// status item's "Show Last Run Log" — Inspect reports land here too. The
// window wears the wireframe skin the way the settings card does.

import SwiftUI

/// The debug window's content: the well on paper, filling whatever size
/// the resizable window is dragged to. The top padding clears the bare
/// title strip the close button stands in (28pt — no toolbar here, unlike
/// the console's unified bar).
struct WireLogWindowView: View {
    let controller: RelayController

    var body: some View {
        WireLogWell(controller: controller)
            .padding(.horizontal, Wire.s(16))
            .padding(.bottom, Wire.s(16))
            .padding(.top, 28 + Wire.s(5))
            .frame(minWidth: Wire.s(380), maxWidth: .infinity,
                   minHeight: Wire.s(220), maxHeight: .infinity)
            .background(Wire.paper)
            .environment(\.colorScheme, .light)
    }
}

/// The scrolling tail of the last run's log, following the newest line.
struct WireLogWell: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Wire.s(4)) {
            Text("LAST RUN LOG")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Wire.s(2)) {
                        if controller.logLines.isEmpty {
                            Text("No run yet — the log fills as one goes.")
                                .font(Wire.mono(10.5))
                                .foregroundColor(Wire.faint)
                        }
                        ForEach(controller.logLines) { line in
                            Text(line.text)
                                .font(Wire.mono(10.5))
                                .foregroundColor(Wire.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Wire.s(8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .onChange(of: controller.logLines.count) { _, _ in
                    if let last = controller.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

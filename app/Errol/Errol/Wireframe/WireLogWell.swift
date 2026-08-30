// The log well — the one list on the panel that grows, which is why it
// sits in its own view. See WireframePanelView for the skin.

import SwiftUI

struct WireLogWell: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Wire.s(4)) {
            Text("LOG")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Wire.s(2)) {
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

import SwiftUI

/// The one capsule every phase shares — permission aside, which has its
/// own view in the same shape: the participants at opposite ends, the
/// content between them changing with the stage (guided setup, the editor,
/// the exchange, the ending), the actions beside it. Its natural content
/// height drives the native window; longer text grows it downward.
struct PerchPanelView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: Perch.s(14)) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            // The center between its two hairlines, as the reference draws
            // it: the meter at its top left and the settings at its top
            // right in every state, the stage's content under them, and —
            // outside the guided steps, whose actions sit under their own
            // copy — the stage's actions beside it.
            HStack(alignment: .center, spacing: Perch.s(10)) {
                VStack(alignment: .leading, spacing: Perch.s(8)) {
                    HStack(alignment: .center, spacing: Perch.s(8)) {
                        if showsMeter {
                            PerchProgressMeter(controller: controller)
                                .transition(.opacity)
                        }
                        Spacer(minLength: 0)
                        PerchWidgetSetup(controller: controller)
                    }
                    .animation(Perch.fade, value: showsMeter)
                    PerchWidgetCenter(controller: controller)
                }
                .layoutPriority(1)
                PerchWidgetActions(controller: controller)
            }
            .padding(.horizontal, Perch.s(18))
            .overlay(alignment: .leading) { hairline }
            .overlay(alignment: .trailing) { hairline }
            .layoutPriority(1)
            PerchParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, Perch.s(28))
        .padding(.vertical, Perch.s(12))
        .frame(width: width)
        .frame(minHeight: Perch.widgetHeight)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Perch.accent)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .clipShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onCardResize?($0) }
    }

    /// The four-segment meter: through the guided steps and on first
    /// reaching the editor; gone once a run has started.
    private var showsMeter: Bool {
        (controller.stage == .setup || controller.stage == .compose) && controller.setup.state.meterVisible
    }

    /// The center's edges, the height of whatever the center holds.
    private var hairline: some View {
        Rectangle().fill(Perch.hairline).frame(width: 1)
    }
}

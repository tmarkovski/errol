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
        HStack(spacing: Perch.s(18)) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            separator
            VStack(alignment: .leading, spacing: Perch.s(8)) {
                if showsMeter {
                    PerchProgressMeter(controller: controller)
                        .transition(.opacity)
                }
                PerchWidgetCenter(controller: controller)
            }
            .layoutPriority(1)
            .animation(Perch.fade, value: showsMeter)
            PerchWidgetActions(controller: controller)
            separator
            PerchParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, Perch.s(24))
        .padding(.vertical, Perch.s(18))
        .frame(width: width)
        .frame(minHeight: Perch.widgetHeight)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Perch.accent)
        .background(Perch.paper.gesture(WindowDragGesture()))
        .clipShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onCardResize?($0) }
    }

    /// The four-segment meter: through the guided steps and on first
    /// reaching the editor; gone once a run has started.
    private var showsMeter: Bool {
        (controller.stage == .setup || controller.stage == .compose) && controller.setup.state.meterVisible
    }

    private var separator: some View {
        Rectangle().fill(Perch.hairline)
            .frame(width: 1, height: Perch.s(58))
    }
}

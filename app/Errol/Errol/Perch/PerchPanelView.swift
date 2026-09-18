import SwiftUI

/// The one capsule every phase shares — permission aside, which has its
/// own view in the same shape: the participants at opposite ends, the
/// content between them changing with the stage (guided setup, the editor,
/// the exchange, the ending), the actions beside it. Its footprint stays
/// fixed; editors and additional run details scroll inside the content area.
struct PerchPanelView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: Perch.s(14)) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            // The toolbar and trailing action share an x-coordinate. Setup
            // and the running state put their actions beside supporting copy.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Perch.s(8)) {
                    if showsMeter {
                        PerchProgressMeter(controller: controller)
                            .transition(.opacity)
                    } else if controller.stage == .running {
                        PerchRunMetadata(controller: controller)
                    }
                    Spacer(minLength: 0)
                    PerchWidgetSetup(controller: controller)
                }
                .animation(Perch.fade, value: showsMeter)
                PerchWidgetCenter(controller: controller)
                    .padding(.top, Perch.s(8))
                    .frame(maxHeight: .infinity, alignment: .top)
                if controller.stage == .compose || controller.stage == .finished
                    || (controller.stage == .running && controller.isSteering) {
                    PerchWidgetActions(controller: controller)
                        .padding(.top, Perch.s(6))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Perch.s(18))
            .overlay(alignment: .leading) { hairline }
            .overlay(alignment: .trailing) { hairline }
            .layoutPriority(1)
            PerchParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, Perch.s(28))
        .padding(.vertical, Perch.s(12))
        .frame(width: width, height: Perch.widgetHeight)
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

    /// The center's edges, the height of the column — which is the
    /// capsule's, now that the column fills it.
    private var hairline: some View {
        Rectangle().fill(Perch.hairline).frame(width: 1)
    }
}

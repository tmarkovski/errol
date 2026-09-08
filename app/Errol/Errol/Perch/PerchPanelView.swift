import SwiftUI

/// The widget has one shared surface, with the participants at opposite ends.
/// Its natural content height drives the native window; longer drafts grow it.
struct PerchPanelView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: Perch.s(18)) {
            PerchWidgetParticipant(controller: controller, speaker: .chatgpt)
            separator
            PerchWidgetCenter(controller: controller)
                .layoutPriority(1)
            PerchWidgetActions(controller: controller)
            separator
            PerchWidgetParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, Perch.s(24))
        .padding(.vertical, Perch.s(22))
        .frame(width: width)
        .frame(minHeight: Perch.widgetHeight)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Perch.accent)
        .background(Perch.paper.gesture(WindowDragGesture()))
        .clipShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onCardResize?($0) }
    }

    private var separator: some View {
        Rectangle().fill(Perch.hairline)
            .frame(width: 1, height: Perch.s(58))
    }
}

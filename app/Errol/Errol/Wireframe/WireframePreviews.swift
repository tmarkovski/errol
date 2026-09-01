// Every canvas the skin is worked on in, kept out of the view files so a
// preview added for one afternoon does not sit in the middle of the part
// it was previewing.

import SwiftUI

#Preview("Wireframe console (idle)") {
    WireframePanelView(controller: RelayController())
        .background(Color(white: 0.75))
}

#Preview("Wireframe console (in run)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.currentTurn = 7
    controller.chatgptConversation = .chatting
    controller.claudeConversation = .waiting
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#Preview("Wireframe steer (held at handoff)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.currentTurn = 4
    controller.isPaused = true
    controller.isHolding = true
    controller.setSteeringText("Drop the notification idea; go deeper on the lamps.")
    controller.chatgptConversation = .replied
    controller.claudeConversation = .waiting
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#Preview("Wireframe run ended") {
    let controller = RelayController()
    controller.currentTurn = 6
    controller.lastRunDuration = 272
    controller.chatgptConversation = .ended
    controller.claudeConversation = .ended
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#if DEBUG
/// The one preview that moves: it hands the conversation back and forth
/// every couple of seconds, so the counter's roll and the pointer's swing
/// play in the canvas while the head unit is being edited. Every other
/// preview here is a frozen state, and a frozen state cannot show an
/// animation that has stopped working.
private struct WireframeHandoffPreview: View {
    @State private var controller: RelayController = {
        let c = RelayController()
        c.isRunning = true
        c.currentTurn = 1
        c.conversation = "Debate"
        c.topic = "Are code comments for the why or the what?"
        c.chatgptConversation = .chatting
        c.claudeConversation = .waiting
        return c
    }()

    var body: some View {
        WireframePanelView(controller: controller)
            .background(Color(white: 0.75))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    let claudeSpeaks = controller.chatgptConversation == .chatting
                    controller.chatgptConversation = claudeSpeaks ? .waiting : .chatting
                    controller.claudeConversation = claudeSpeaks ? .chatting : .waiting
                    controller.currentTurn += 1
                }
            }
    }
}

#Preview("Wireframe handoff (animated)") {
    WireframeHandoffPreview()
}
#endif

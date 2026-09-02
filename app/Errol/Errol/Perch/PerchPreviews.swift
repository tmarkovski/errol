// Every canvas the panel is worked on in, kept out of the view files so
// each of those stays about its view.

import SwiftUI

#Preview("Perch console (idle)") {
    PerchPanelView(controller: RelayController())
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch avatars (icon and fallback)") {
    // The first wears whatever Claude Desktop's icon is on this Mac; the
    // second names no installed app, so it is the initial-in-a-circle
    // fallback the head uses when an app is missing.
    HStack(spacing: Perch.s(24)) {
        PerchAvatar(bundleID: config.claudeBundleID, initial: "C",
                    feather: Perch.claudeFeather, presence: Perch.presence)
        PerchAvatar(bundleID: "com.example.not-installed", initial: "C",
                    feather: Perch.claudeFeather, presence: Perch.red)
    }
    .padding(Perch.s(24))
    .background(Perch.paper)
}

#Preview("Perch console (in run)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.currentTurn = 4
    controller.limitTurns = true
    controller.turns = 10
    controller.chatgptConversation = .waiting
    controller.claudeConversation = .chatting
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch steer (holding)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.currentTurn = 4
    controller.chatgptConversation = .waiting
    controller.claudeConversation = .chatting
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch run ended") {
    let controller = RelayController()
    controller.currentTurn = 6
    controller.lastRunDuration = 272
    controller.chatgptConversation = .ended
    controller.claudeConversation = .ended
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#if DEBUG
/// The one preview that moves: it hands the conversation back and forth
/// every couple of seconds so the bead's hop plays in the canvas.
private struct PerchHandoffPreview: View {
    @State private var controller: RelayController = {
        let c = RelayController()
        c.isRunning = true
        c.currentTurn = 1
        c.chatgptConversation = .chatting
        c.claudeConversation = .waiting
        return c
    }()

    var body: some View {
        PerchPanelView(controller: controller)
            .padding(24)
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

#Preview("Perch handoff (animated)") {
    PerchHandoffPreview()
}
#endif

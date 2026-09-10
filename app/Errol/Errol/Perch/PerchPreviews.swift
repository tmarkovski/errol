// Every canvas the panel is worked on in, kept out of the view files so
// each of those stays about its view. Each runs on PerchPreviewEngine, so
// the controls do what they do in the app — Run starts a run, Stop ends it
// at the next handoff and leaves the summary, Pause holds it at the next
// handoff and opens the field, Return sends the note, New session clears
// the summary — and nothing reaches either app. A canvas that opens
// mid-run starts its run here, from the turn its engine is told to open
// on, and the run then goes on at the engine's pace until the cap or Stop.

import SwiftUI

#if DEBUG
/// A controller on a preview engine with the form filled in, so Start has
/// something to send.
private func previewController(_ engine: PerchPreviewEngine = PerchPreviewEngine()) -> RelayController {
    let controller = RelayController(engine: engine)
    controller.topic = "Pricing by seat or by usage"
    return controller
}

#Preview("Perch console (idle)") {
    PerchPanelView(controller: previewController())
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch console (Free chat)") {
    let controller = previewController()
    controller.selectConversation(RelayController.freeConversation)
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch console (long prompt)") {
    let controller = previewController()
    controller.topic = Array(repeating: "Compare pricing by seat and by usage. Consider predictability, fairness, and how each option grows with a team.", count: 8)
        .joined(separator: "\n\n")
    return PerchPanelView(controller: controller)
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
    // Opens on turn 4 of 10, Claude writing.
    let controller = previewController(PerchPreviewEngine(turn: 4))
    controller.limitTurns = true
    controller.turns = 10
    controller.start()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch steer (queued)") {
    // The note is in the mailbox; it rides the handoff after Claude's
    // reply, and its echo the one after that.
    let controller = previewController(PerchPreviewEngine(turn: 4))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    controller.sendSteering()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch steer (field open, holding)") {
    // Claude's reply is ready to capture, so the pause holds at once.
    let controller = previewController(PerchPreviewEngine(turn: 4, atHandoff: true))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch run ended") {
    // A run's leavings, set directly: what the panel shows once the engine
    // has posted .finished — the summary where the field was, New session
    // at the foot. New session clears them and Run begins a fresh preview
    // run, as in the app.
    let controller = previewController()
    controller.currentTurn = 6
    controller.lastReport = RunReport(outcome: .completed, repliesCaptured: 6)
    controller.lastRunDuration = 272
    controller.chatgptConversation = .ended
    controller.claudeConversation = .ended
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch run stopped (played)") {
    // A short run stopped from the foot: Stop dims and the line says the
    // end is coming, then the summary reads "Run stopped". Both sides sign
    // off from turn 8, so left alone it completes instead.
    let controller = previewController(PerchPreviewEngine(pace: .seconds(2), signOffAt: 8))
    controller.start()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch steer (pausing during copy)") {
    let controller = previewController(PerchPreviewEngine(turn: 4, openingOperation: .capture))
    controller.start()
    controller.beginSteering()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch steer (pausing during send)") {
    let controller = previewController(PerchPreviewEngine(turn: 4, openingOperation: .delivery))
    controller.start()
    controller.beginSteering()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Perch handoff (animated)") {
    // The quick one: replies take two seconds and nobody signs off, so the
    // bead's hop plays over and over until Stop.
    let controller = previewController(PerchPreviewEngine(pace: .seconds(2.2)))
    controller.start()
    return PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}
#endif

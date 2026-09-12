// Every canvas the panel is worked on in, kept out of the view files so
// each of those stays about its view. Each runs on PerchPreviewEngine, so
// the controls do what they do in the app — Open opens an app, Choose a
// window offers the engine's canned windows, Connect binds one, Send
// starts a run, Stop ends it at the next handoff and leaves the summary,
// Pause to steer holds it and opens the field, Return sends the note —
// and nothing reaches either app. The ten reference screens are here in
// order (docs/design-proposals/setup-interaction/SPEC.md); the first,
// permission, is PanelNavigation's canvas.

import SwiftUI

#if DEBUG
/// A controller on a preview engine, with the form filled in so Send has
/// something to send.
private func previewController(_ engine: PerchPreviewEngine = PerchPreviewEngine()) -> RelayController {
    let controller = RelayController(engine: engine)
    controller.topic = "Pricing by seat or by usage"
    return controller
}

/// The guided steps taken up to `phase`, on a controller whose apps are
/// both ready: the preview engine answers each step at once.
private func stepped(to phase: SetupPhase, _ engine: PerchPreviewEngine = PerchPreviewEngine()) -> RelayController {
    let controller = previewController(engine)
    let setup = controller.setup
    if phase == .prepareApps { return controller }
    setup.continueFromPrepare()
    if phase == .arrange { return controller }
    setup.continueFromArrange()
    if phase == .connect(.chatgpt) { return controller }
    setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    if phase == .connect(.claude) { return controller }
    setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeConversation)
    return controller
}

private func canvas(_ controller: RelayController) -> some View {
    PerchPanelView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

// MARK: Setup

#Preview("02 · Open apps (ChatGPT closed)") {
    // ChatGPT is installed but not running: its icon opens it, and the
    // preview engine brings it up a moment later.
    var closed = PerchPreviewEngine.bothReady
    closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
    return canvas(previewController(PerchPreviewEngine(readiness: closed)))
}

#Preview("02 · Open apps (Claude not installed)") {
    var missing = PerchPreviewEngine.bothReady
    missing.claude = SideStatus(appName: "Claude", state: .missing, headline: "Not running")
    return canvas(previewController(PerchPreviewEngine(readiness: missing,
                                                       installed: [.chatgpt: true, .claude: false])))
}

#Preview("02 · Open apps (both ready)") {
    canvas(stepped(to: .prepareApps))
}

#Preview("03 · Arrange") {
    canvas(stepped(to: .arrange))
}

#Preview("04 · Connect ChatGPT") {
    canvas(stepped(to: .connect(.chatgpt)))
}

#Preview("04 · Connect ChatGPT (picking)") {
    let controller = stepped(to: .connect(.chatgpt))
    controller.setup.beginPicking(.chatgpt)
    return canvas(controller)
}

#Preview("05 · Connect Claude") {
    canvas(stepped(to: .connect(.claude)))
}

#Preview("05 · Connect Claude (Code session chosen)") {
    // A work surface is a deliberate choice: the icon's details offer
    // Use this session, and Send waits for it.
    let controller = stepped(to: .connect(.claude))
    controller.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeCode)
    return canvas(controller)
}

// MARK: Compose, run, pause, end

#Preview("06 · Compose") {
    canvas(stepped(to: .compose))
}

#Preview("06 · Compose (Free chat)") {
    let controller = stepped(to: .compose)
    controller.selectConversation(RelayController.freeConversation)
    return canvas(controller)
}

#Preview("06 · Compose (long topic)") {
    let controller = stepped(to: .compose)
    controller.topic = Array(repeating: "Compare pricing by seat and by usage. Consider predictability, fairness, and how each option grows with a team.", count: 8)
        .joined(separator: "\n\n")
    return canvas(controller)
}

#Preview("07 · Running") {
    // Opens on turn 4 of 10, Claude writing.
    let controller = stepped(to: .compose, PerchPreviewEngine(turn: 4))
    controller.limitTurns = true
    controller.turns = 10
    controller.start()
    return canvas(controller)
}

#Preview("08 · Pause (field open, holding)") {
    // Claude's reply is ready to capture, so the pause holds at once.
    let controller = stepped(to: .compose, PerchPreviewEngine(turn: 4, atHandoff: true))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    return canvas(controller)
}

#Preview("08 · Pause (queued note)") {
    // The note is in the mailbox; it rides the handoff after Claude's
    // reply, and its echo the one after that.
    let controller = stepped(to: .compose, PerchPreviewEngine(turn: 4))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    controller.sendSteering()
    return canvas(controller)
}

#Preview("08 · Pause (pausing during copy)") {
    let controller = stepped(to: .compose, PerchPreviewEngine(turn: 4, openingOperation: .capture))
    controller.start()
    controller.beginSteering()
    return canvas(controller)
}

#Preview("09 · Finished") {
    // A run's leavings, set directly: what the panel shows once the engine
    // has posted .finished — the summary where the field was, the two next
    // intentions beside it.
    let controller = stepped(to: .compose)
    controller.setup.runStarted()
    controller.currentTurn = 6
    controller.lastReport = RunReport(outcome: .completed, repliesCaptured: 6)
    controller.lastRunDuration = 272
    controller.chatgptConversation = .ended
    controller.claudeConversation = .ended
    return canvas(controller)
}

#Preview("09 · Finished (stopped, played)") {
    // A short run stopped from the actions: Stop dims and the line says the
    // end is coming, then the summary reads "Run stopped". Both sides sign
    // off from turn 8, so left alone it completes instead.
    let controller = stepped(to: .compose, PerchPreviewEngine(pace: .seconds(2), signOffAt: 8))
    controller.start()
    return canvas(controller)
}

#Preview("10 · Return (another topic here)") {
    let controller = stepped(to: .compose)
    controller.setup.runStarted()
    controller.lastReport = RunReport(outcome: .completed, repliesCaptured: 6)
    controller.lastRunDuration = 272
    controller.anotherTopicHere()
    return canvas(controller)
}

// MARK: Pieces

#Preview("Avatars (icon and fallback)") {
    // The first wears whatever Claude Desktop's icon is on this Mac; the
    // second names no installed app, so it is the initial-in-a-circle
    // fallback the column uses when an app is missing.
    HStack(spacing: Perch.s(24)) {
        PerchAvatar(bundleID: config.claudeBundleID, initial: "C",
                    feather: Perch.claudeFeather, presence: Perch.presence, check: true)
        PerchAvatar(bundleID: "com.example.not-installed", initial: "C",
                    feather: Perch.claudeFeather, presence: Perch.red)
    }
    .padding(Perch.s(24))
    .background(Perch.paper)
}

#Preview("Handoff (animated)") {
    // The quick one: replies take two seconds and nobody signs off, so the
    // transfer plays over and over until Stop.
    let controller = stepped(to: .compose, PerchPreviewEngine(pace: .seconds(2.2)))
    controller.start()
    return canvas(controller)
}
#endif

// Scratchpad harness for a UX review: renders Errol's console (Perch) in each
// stage, offscreen, from the app's own sources, driven by PerchPreviewEngine.
// Nothing here touches either chat app, the Errol bundle, or its signing.
// The capsule wears the theme's shell, as the panel does; AppKit's window
// shadow gets a stand-in, over a backdrop like a chat window. `-appTheme
// warm-stone` renders another theme: UserDefaults reads it from the
// arguments, so nothing is saved.

import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let dark = CommandLine.arguments.contains("--dark")
/// What stands behind the console, like a chat window in either appearance.
let backdrop = dark ? Color(white: 0.11) : Color(red: 0.925, green: 0.93, blue: 0.94)

@MainActor
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
    }
}

@MainActor
func pumpUntil(_ timeout: Double, _ done: () -> Bool) {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end, !done() {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
}

/// The capsule and, during a run, the transcript window under it, the way
/// MenuBarController stands them: centered, a gap apart.
struct Scene: View {
    let controller: RelayController
    let transcript: Bool
    var consoleWidth: CGFloat = Perch.widgetWidth

    var body: some View {
        VStack(spacing: PerchTranscript.gap) {
            PerchConsoleView(controller: controller, width: consoleWidth)
                .background(Capsule().fill(Perch.shell))
                .overlay(Capsule().stroke(Color.black.opacity(dark ? 0.5 : 0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
            if transcript {
                PerchTranscript(controller: controller)
                    .frame(width: PerchConsoleView.promptBoxWidth(consoleWidth: consoleWidth),
                           height: PerchTranscript.height)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(width: consoleWidth + 72, height: 36 + 156 + (transcript ? PerchTranscript.gap + PerchTranscript.height : 0) + 36,
               alignment: .top)
        .background(backdrop)
    }
}

/// A side's details where the app puts them: the card under the console,
/// its arrow on the side's icon (PerchDetailsAnchor.Coordinator.place), over
/// the transcript during a run. The panel's own shadow gets a stand-in.
struct DetailsScene: View {
    let controller: RelayController
    let speaker: Speaker
    var transcript = false
    @State private var placement = PerchDetailsPlacement()
    @State private var cardWidth = PerchParticipantPopover.width

    static let height: CGFloat = 36 + 156 + 330 + 36

    var body: some View {
        let icon = PerchConsoleView.endInset + Perch.participantWidth / 2
        let lead = Perch.s(50)
        let x = speaker == .chatgpt ? icon - lead : Perch.widgetWidth - icon + lead - cardWidth
        ZStack(alignment: .topLeading) {
            Scene(controller: controller, transcript: transcript)
                .frame(height: Self.height, alignment: .top)
            PerchDetailsCallout(placement: placement,
                                content: PerchParticipantPopover(controller: controller, speaker: speaker)) { size in
                cardWidth = size.width
            }
            .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
            .offset(x: 36 + x, y: 36 + 156 + Perch.s(4))
        }
        .frame(width: Perch.widgetWidth + 72, height: Self.height, alignment: .topLeading)
        .background(backdrop)
        .onAppear { placement.arrowX = speaker == .chatgpt ? lead : cardWidth - lead }
        .onChange(of: cardWidth) { _, width in placement.arrowX = speaker == .chatgpt ? lead : width - lead }
    }
}

@MainActor
func details(_ name: String, _ controller: RelayController, _ speaker: Speaker, transcript: Bool = false) {
    render(name, DetailsScene(controller: controller, speaker: speaker, transcript: transcript),
           size: CGSize(width: Perch.widgetWidth + 72, height: DetailsScene.height), settle: 0.6)
}

@MainActor
func render(_ name: String, _ view: some View, size: CGSize, settle: Double) {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: NSRect(x: -40000, y: -40000, width: size.width, height: size.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    pump(settle)
    host.layoutSubtreeIfNeeded()
    pump(0.3)
    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let suffix = dark ? "-dark" : ""
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)\(suffix).png"))
        print("wrote \(name)\(suffix).png")
    }
    window.close()
}

@MainActor
func scene(_ name: String, _ controller: RelayController, transcript: Bool = false, settle: Double = 1.5) {
    let height = 36 + 156 + (transcript ? PerchTranscript.gap + PerchTranscript.height : 0) + 36
    render(name, Scene(controller: controller, transcript: transcript),
           size: CGSize(width: Perch.widgetWidth + 72, height: height), settle: settle)
}

/// Replies already in the transcript, and a note sent with the third
/// handoff, as PerchTranscript's canvases play them.
@MainActor
func play(_ engine: PerchPreviewEngine, replies: Int, note: Bool = true) {
    let text = "Push on the pricing question before you wrap up."
    for turn in stride(from: 1, through: replies, by: 1) {
        engine.events.post(.reply(side: turn % 2 == 1 ? .chatgpt : .claude, text: PerchPreviewEngine.reply(turn: turn)))
        if note, turn == 3 {
            engine.events.post(.steeringCommitted(note: text, recipient: .claude, turn: 3))
            engine.events.post(.steering(SteeringDelivery(leg: .note, note: text, recipient: .claude, turn: 3,
                                                          outcome: .delivered)))
        }
    }
}

@MainActor
func quick(_ controller: RelayController) -> RelayController {
    controller.summarize = { _ in
        try? await Task.sleep(for: .milliseconds(150))
        return "Whether to price by seat or by usage"
    }
    controller.summarizeReply = { reply in PerchPreviewEngine.gist(for: reply) }
    return controller
}

@MainActor
func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    // Scene names, leaving out the flags and each `-key value` default.
    var only: [String] = []
    var arguments = CommandLine.arguments.dropFirst(2).makeIterator()
    while let argument = arguments.next() {
        if argument.hasPrefix("--") { continue }
        if argument.hasPrefix("-") { _ = arguments.next(); continue }
        only.append(argument)
    }
    func wanted(_ name: String) -> Bool { only.isEmpty || only.contains { name.hasPrefix($0) } }

    try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    // Before a run.
    if wanted("01") {
        let c = quick(RelayController(engine: PerchPreviewEngine()))
        scene("01-compose-several-conversations", c)
        details("01-participant-choose", c, .chatgpt)
    }
    if wanted("02") {
        let c = quick(connectedController())
        c.topic = ""
        scene("02-compose-connected-empty", c)
    }
    if wanted("03") {
        let c = quick(connectedController())
        scene("03-compose-connected-topic", c)
        render("03-narrow", Scene(controller: c, transcript: false, consoleWidth: 600),
               size: CGSize(width: 672, height: 228), settle: 0.5)
        details("03-participant", c, .chatgpt)
    }
    if wanted("04") {
        var closed = PerchPreviewEngine.bothReady
        closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
        let c = quick(RelayController(engine: PerchPreviewEngine(readiness: closed)))
        scene("04-compose-chatgpt-closed", c)
        details("04-participant-closed", c, .chatgpt)
    }
    if wanted("05") {
        let c = quick(RelayController(engine: PerchPreviewEngine()))
        c.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
        c.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeCode)
        scene("05-compose-code-session", c)
    }
    if wanted("06") {
        let c = quick(connectedController())
        c.topic = Array(repeating: "Compare pricing by seat and by usage. Consider predictability, fairness, and how each option grows with a team.", count: 3)
            .joined(separator: "\n\n")
        scene("06-compose-long-topic", c)
    }

    // A run.
    if wanted("07") {
        // Just started: the opening is on its way to the first side.
        let c = quick(connectedController(PerchPreviewEngine(pace: .seconds(120))))
        c.ending = .turnLimit
        c.turns = 10
        c.start()
        scene("07-running-opening", c, transcript: true, settle: 0.8)
    }
    if wanted("08") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.ending = .turnLimit
        c.turns = 10
        c.start()
        pump(0.5)
        play(engine, replies: 4)
        scene("08-running-mid", c, transcript: true, settle: 0.5)
        precondition(!c.consoleAccess.canShowWindow)
        details("08-participant", c, .chatgpt, transcript: true)
    }
    if wanted("09") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5, atHandoff: true)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        play(engine, replies: 4, note: false)
        c.beginSteering()
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        c.setSteeringText("Push on the pricing question before you wrap up.")
        scene("09-paused-writing-note", c, transcript: true, settle: 0.5)
        precondition(c.consoleAccess.canShowWindow)
        precondition(!c.consoleAccess.canChangeDestination)
        c.showWindow(.chatgpt)
        precondition(c.isSteering && c.steeringText.contains("Push on"))
        precondition(c.isShowingWindow && !c.consoleAccess.canResume)
        c.sendSteering()
        precondition(c.isSteering, "Resume must wait for Show window")
        pumpUntil(3) { !c.isShowingWindow }
        precondition(c.consoleAccess.canResume && c.steeringText.contains("Push on"))
        precondition(engine.control.isPaused)
        precondition(engine.control.beginOperation(.capture) == .hold)
        precondition(engine.control.beginOperation(.delivery) == .hold)
    }
    if wanted("10") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        play(engine, replies: 4, note: false)
        c.beginSteering()
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        c.setSteeringText("Push on the pricing question before you wrap up.")
        c.sendSteering()
        scene("10-note-queued", c, transcript: true, settle: 2.5)
    }
    if wanted("11") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        play(engine, replies: 4)
        engine.events.post(.blocked(.notInFront(side: .claude)))
        scene("11-focus-alert", c, transcript: true, settle: 2.0)
    }
    if wanted("12") {
        // A short run played to its mutual sign-off.
        let engine = PerchPreviewEngine(pace: .milliseconds(500), signOffAt: 5)
        let c = quick(connectedController(engine))
        c.start()
        pumpUntil(60) { c.stage == .finished }
        scene("12-finished", c, transcript: true, settle: 2.0)
    }
    if wanted("13") {
        let height: CGFloat = 36 + 156 + 36
        render("13-permission",
               PermissionOnboardingView(width: Perch.widgetWidth)
                   .frame(width: Perch.widgetWidth, height: 156)
                   .background(Capsule().fill(Perch.shell))
                   .clipShape(Capsule())
                   .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
                   .padding(36)
                   .frame(width: Perch.widgetWidth + 72, height: height, alignment: .top)
                   .background(backdrop),
               size: CGSize(width: Perch.widgetWidth + 72, height: height), settle: 1.0)
    }
    if wanted("14") {
        let engine = PerchPreviewEngine(pace: .seconds(120), openingOperation: .delivery)
        let c = quick(connectedController(engine))
        c.start()
        c.beginSteering()
        precondition(c.isSteeringPending && !c.isSteering)
        precondition(!c.consoleAccess.canShowWindow)
        c.showWindow(.claude)
        precondition(!c.isShowingWindow)
        scene("14-pause-pending", c, transcript: true, settle: 0.01)
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        precondition(c.consoleAccess.pauseGranted)
        c.stop()
    }
    if wanted("15") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        engine.events.post(.blocked(.windowHidden(side: .claude, seen: "minimized")))
        scene("15-held", c, transcript: true, settle: 0.3)
        details("15-participant-held", c, .claude, transcript: true)
        c.stop()
    }
    if wanted("16") {
        for (name, outcome) in [("complete", RunOutcome.completed), ("stopped", .stopped),
                                ("interrupted", .sendAbandoned(side: .claude))] {
            let c = quick(connectedController())
            c.setup.runStarted()
            c.lastReport = RunReport(outcome: outcome, repliesCaptured: 6)
            c.lastRunDuration = 72
            scene("16-finished-" + name, c, transcript: true, settle: 0.2)
        }
    }
    if wanted("18") {
        // The endings: a turn limit, with its stepper beside the chip, and a
        // run that only Stop ends, before and during.
        let limited = quick(connectedController())
        limited.ending = .turnLimit
        limited.turns = 12
        scene("18-ending-turn-limit", limited)
        let open = quick(connectedController())
        open.ending = .whenStopped
        scene("18-ending-when-stopped", open)
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let running = quick(connectedController(engine))
        running.ending = .whenStopped
        running.start()
        pump(0.5)
        play(engine, replies: 4, note: false)
        scene("18-ending-when-stopped-running", running, transcript: true, settle: 0.5)
        running.stop()
        let narrow = quick(connectedController())
        narrow.ending = .turnLimit
        render("18-ending-turn-limit-narrow", Scene(controller: narrow, transcript: false, consoleWidth: 600),
               size: CGSize(width: 672, height: 228), settle: 0.5)
    }
    if wanted("17") {
        let c = quick(connectedController())
        var report = ReadinessReport(chatgpt: c.chatgptStatus, claude: c.claudeStatus)
        var left = PerchPreviewEngine.chatgptWindows[0]
        left.identity.title = "Pricing critique — enterprise tier, second pass"
        var right = PerchPreviewEngine.claudeWindows[0]
        right.identity.title = "Pricing critique — enterprise tier, first pass"
        right.identity.surface = "Code"
        report.candidates = [.chatgpt: [left], .claude: [right]]
        c.setup.apply(report)
        scene("17-long-destinations", c, settle: 0.3)
    }
    if wanted("19") {
        // Settings, in the card the panel turns into: the shell, with its
        // fields in wells.
        let navigation = PanelNavigation(accessibilityGranted: true)
        navigation.showsSettings = true
        let card = PanelRootView(controller: quick(RelayController(engine: PerchPreviewEngine())),
                                 navigation: navigation)
            .background(Perch.shell)
            .clipShape(RoundedRectangle(cornerRadius: Perch.shellCorner))
        let height = 36 + NSHostingView(rootView: card).fittingSize.height + 36
        render("19-settings",
               card
                   .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
                   .padding(36)
                   .frame(width: Perch.cardWidth + 72, height: height, alignment: .top)
                   .background(backdrop),
               size: CGSize(width: Perch.cardWidth + 72, height: height), settle: 1.0)
    }

}

MainActor.assumeIsolated { main() }

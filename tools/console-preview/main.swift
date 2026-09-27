// Scratchpad harness for a UX review: renders Errol's console (Perch) in each
// stage, offscreen, from the app's own sources, driven by PerchPreviewEngine.
// Nothing here touches either chat app, the Errol bundle, or its signing.
// Each stage stands in the Xcode canvases' scene (PerchPreviewScene): the
// capsule on the theme's shell, as the panel has it, with stand-ins for
// AppKit's window shadows, over a backdrop like a chat window. `canvas`
// renders every canvas's state (PerchPreviewState). `-appTheme warm-stone`
// renders another theme: UserDefaults reads it from the arguments, so
// nothing is saved.

import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let dark = CommandLine.arguments.contains("--dark")
let backdrop = PerchPreviewScene.backdrop(dark ? .dark : .light)

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

/// A side's tip where the app puts it, as the pointer on its icon brings it
/// up: under the console, its outer edge on the icon's, over the transcript
/// during a run.
@MainActor
func details(_ name: String, _ controller: RelayController, _ speaker: Speaker) {
    render(name, PerchPreviewScene(controller: controller, details: speaker),
           size: PerchPreviewScene.size(summary: controller.stage != .compose, details: true), settle: 0.6)
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

/// The console, and the transcript under it once a run has begun.
@MainActor
func scene(_ name: String, _ controller: RelayController, consoleWidth: CGFloat = Perch.widgetWidth,
           settle: Double = 1.5) {
    render(name, PerchPreviewScene(controller: controller, consoleWidth: consoleWidth),
           size: PerchPreviewScene.size(summary: controller.stage != .compose, consoleWidth: consoleWidth),
           settle: settle)
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
        scene("01-compose-several-windows", c)
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
        scene("03-narrow", c, consoleWidth: 600, settle: 0.5)
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
        scene("07-running-opening", c, settle: 0.8)
    }
    if wanted("08") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.ending = .turnLimit
        c.turns = 10
        c.start()
        pump(0.5)
        engine.postReplies(4)
        scene("08-running-mid", c, settle: 0.5)
        precondition(!c.consoleAccess.canShowWindow)
        details("08-participant", c, .chatgpt)
    }
    if wanted("09") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5, atHandoff: true)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        engine.postReplies(4, note: false)
        c.beginSteering()
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        c.setSteeringText("Push on the pricing question before you wrap up.")
        scene("09-paused-writing-note", c, settle: 0.5)
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
        engine.postReplies(4, note: false)
        c.beginSteering()
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        c.setSteeringText("Push on the pricing question before you wrap up.")
        c.sendSteering()
        scene("10-note-queued", c, settle: 2.5)
    }
    if wanted("11") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        engine.postReplies(4)
        engine.events.post(.blocked(.notInFront(side: .claude)))
        scene("11-focus-alert", c, settle: 2.0)
    }
    if wanted("12") {
        // A short run played to its mutual sign-off.
        let engine = PerchPreviewEngine(pace: .milliseconds(500), signOffAt: 5)
        let c = quick(connectedController(engine))
        c.start()
        pumpUntil(60) { c.stage == .finished }
        scene("12-finished", c, settle: 2.0)
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
        scene("14-pause-pending", c, settle: 0.01)
        pumpUntil(3) { c.consoleAccess.pauseGranted }
        precondition(c.consoleAccess.pauseGranted)
        c.stop()
    }
    if wanted("15") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        engine.events.post(.blocked(.windowHidden(side: .claude, seen: "minimized")))
        scene("15-held", c, settle: 0.3)
        details("15-participant-held", c, .claude)
        c.stop()
    }
    if wanted("16") {
        for (name, outcome) in [("complete", RunOutcome.completed), ("stopped", .stopped),
                                ("interrupted", .sendAbandoned(side: .claude))] {
            let c = quick(connectedController())
            c.setup.runStarted()
            c.lastReport = RunReport(outcome: outcome, repliesCaptured: 6)
            c.lastRunDuration = 72
            scene("16-finished-" + name, c, settle: 0.2)
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
        engine.postReplies(4, note: false)
        scene("18-ending-when-stopped-running", running, settle: 0.5)
        running.stop()
        let narrow = quick(connectedController())
        narrow.ending = .turnLimit
        scene("18-ending-turn-limit-narrow", narrow, consoleWidth: 600, settle: 0.5)
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

    // The canvases' states, as Xcode draws them (PerchPreviews.swift): asked
    // for by name, `canvas` for all of them or `canvas-05` for one.
    if only.contains(where: { $0.hasPrefix("canvas") }) {
        for (index, state) in PerchPreviewState.allCases.enumerated() {
            let name = String(format: "canvas-%02d-", index + 1) + "\(state)"
            guard wanted(name) else { continue }
            let controller = state.controller()
            render(name, PerchPreviewScene(controller: controller, consoleWidth: state.consoleWidth,
                                           details: state.details),
                   size: PerchPreviewScene.size(summary: controller.stage != .compose, details: state.details != nil,
                                                consoleWidth: state.consoleWidth),
                   settle: 2.5)
        }
    }
}

MainActor.assumeIsolated { main() }

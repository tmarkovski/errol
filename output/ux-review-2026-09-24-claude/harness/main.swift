// Scratchpad harness for a UX review: renders Errol's console (Perch) in each
// stage, offscreen, from the app's own sources, driven by PerchPreviewEngine.
// Nothing here touches either chat app, the Errol bundle, or its signing.
// Liquid Glass does not render offscreen, so the capsule wears a near-white
// stand-in fill with a soft shadow, over a light backdrop like a chat window.

import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let dark = CommandLine.arguments.contains("--dark")

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
                .background(Capsule().fill(surface))
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

    private var surface: Color { dark ? Color(white: 0.17) : Color(white: 0.975) }
    private var backdrop: Color { dark ? Color(white: 0.11) : Color(red: 0.925, green: 0.93, blue: 0.94) }
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
    window.orderOut(nil)
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
    let only = CommandLine.arguments.dropFirst(1).filter { !$0.hasPrefix("--") && $0 != outDir }
    func wanted(_ name: String) -> Bool { only.isEmpty || only.contains { name.hasPrefix($0) } }

    // Before a run.
    if wanted("01") {
        scene("01-compose-several-conversations", quick(RelayController(engine: PerchPreviewEngine())))
    }
    if wanted("02") {
        let c = quick(connectedController())
        c.topic = ""
        scene("02-compose-connected-empty", c)
    }
    if wanted("03") {
        scene("03-compose-connected-topic", quick(connectedController()))
    }
    if wanted("04") {
        var closed = PerchPreviewEngine.bothReady
        closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
        scene("04-compose-chatgpt-closed", quick(RelayController(engine: PerchPreviewEngine(readiness: closed))))
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
        c.limitTurns = true
        c.turns = 10
        c.start()
        scene("07-running-opening", c, transcript: true, settle: 0.8)
    }
    if wanted("08") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.limitTurns = true
        c.turns = 10
        c.start()
        pump(0.5)
        play(engine, replies: 4)
        scene("08-running-mid", c, transcript: true, settle: 2.5)
    }
    if wanted("09") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5, atHandoff: true)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        play(engine, replies: 4, note: false)
        c.beginSteering()
        c.setSteeringText("Push on the pricing question before you wrap up.")
        scene("09-paused-writing-note", c, transcript: true, settle: 2.5)
    }
    if wanted("10") {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let c = quick(connectedController(engine))
        c.start()
        pump(0.5)
        play(engine, replies: 4, note: false)
        c.beginSteering()
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
                   .background(Capsule().fill(dark ? Color(white: 0.17) : Color(white: 0.975)))
                   .clipShape(Capsule())
                   .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
                   .padding(36)
                   .frame(width: Perch.widgetWidth + 72, height: height, alignment: .top)
                   .background(Color(red: 0.925, green: 0.93, blue: 0.94)),
               size: CGSize(width: Perch.widgetWidth + 72, height: height), settle: 1.0)
    }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--converged") {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        renderConverged(outDir: outDir)
    } else if CommandLine.arguments.contains("--mocks") {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        renderMocks(outDir: outDir)
    } else {
        main()
    }
}

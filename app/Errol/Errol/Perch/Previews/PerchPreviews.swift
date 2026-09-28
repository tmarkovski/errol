// What the console's canvases stand on: the scene, the controllers, and one
// state for each thing the console shows. The canvases are in the files
// beside this one, a group to a file (PerchPreviews+Compose and the rest),
// so each file's canvas list stays short. Each stands the console the way
// the panel does (PerchPreviewScene), and each runs on PerchPreviewEngine: the
// controls do what they do in the app, and nothing reaches either app. An
// icon opens its app, a destination line chooses among windows, Start
// relay starts a run, Stop ends it at the next handoff, Pause to steer
// holds it and opens the field, and Return sends the note. The render
// harness (tools/console-preview) draws the same states in the same scene.

#if DEBUG
import SwiftUI

// MARK: - The scene

/// The console as the panel stands it, over a backdrop like a chat window:
/// the capsule on the theme's shell (PanelWindowSurface), with a stand-in
/// for the window's shadow and rim. From a run's start until New topic, the
/// conversation summary stands under it, as MenuBarController shows that
/// window. A side's tip, which the pointer on its icon brings up, can
/// stand there too, where the app puts it, over the summary during a run.
struct PerchPreviewScene: View {
    let controller: RelayController
    var consoleWidth: CGFloat = Perch.widgetWidth
    /// The side whose tip stands under the console.
    var tipSide: Speaker? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var tipWidth: CGFloat = 0

    /// The backdrop's margin around the windows.
    static let margin: CGFloat = 36
    /// The room a tip takes under the console.
    static let tipRoom: CGFloat = 170

    /// The scene's size, which the render harness sizes its window to.
    static func size(summary: Bool, tip: Bool = false,
                     consoleWidth: CGFloat = Perch.widgetWidth) -> CGSize {
        var height = Perch.widgetHeight + (summary ? PerchTranscript.gap + PerchTranscript.height : 0)
        if tip { height = max(height, Perch.widgetHeight + tipRoom) }
        return CGSize(width: consoleWidth + 2 * margin, height: height + 2 * margin)
    }

    /// What stands behind the windows: a chat window, in either appearance.
    static func backdrop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.11) : Color(red: 0.925, green: 0.93, blue: 0.94)
    }

    var body: some View {
        let summary = controller.stage != .compose
        let size = Self.size(summary: summary, tip: tipSide != nil, consoleWidth: consoleWidth)
        ZStack(alignment: .topLeading) {
            VStack(spacing: PerchTranscript.gap) {
                PerchConsoleView(controller: controller, width: consoleWidth)
                    .modifier(PanelWindowSurface())
                    .frame(width: consoleWidth, height: Perch.widgetHeight)
                    .overlay(Capsule().stroke(Color.black.opacity(colorScheme == .dark ? 0.5 : 0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
                if summary {
                    PerchTranscript(controller: controller)
                        .frame(width: PerchMetrics.promptBoxWidth(consoleWidth: consoleWidth),
                               height: PerchTranscript.height)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                }
            }
            .padding(Self.margin)
            if let tipSide { tip(tipSide) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Self.backdrop(colorScheme))
    }

    /// The tip where PerchTipAnchor puts its panel: a step under the
    /// console, its outer edge on the icon's, running inward.
    private func tip(_ side: Speaker) -> some View {
        let edge = PerchMetrics.endInset + (Perch.participantWidth - PerchAvatar.slot) / 2
        let x = side == .chatgpt ? edge : consoleWidth - edge - tipWidth
        return PerchTip(content: PerchParticipantTip(controller: controller, speaker: side)) { size in
            tipWidth = size.width
        }
        .offset(x: Self.margin + x, y: Self.margin + Perch.widgetHeight + PerchTipAnchor<EmptyView>.Coordinator.gap)
    }
}

// MARK: - The states

/// A controller with the run options a freshly launched app has. A run
/// writes its options into the process-wide config, and a new controller
/// takes them from there, so they go back to their defaults first: a
/// canvas never starts from the last one's run.
func freshController(_ engine: PerchPreviewEngine = PerchPreviewEngine()) -> RelayController {
    let defaults = Config()
    config.ending = defaults.ending
    config.turns = defaults.turns
    config.first = defaults.first
    return RelayController(engine: engine)
}

/// Both sides connected, with the form filled in so Start relay has
/// something to send. The model's sentences, for the topic and for each
/// reply, come from the played run's own table a beat later, the way the
/// model's would. The transcript's canvases (PerchTranscript.swift) start
/// from it too.
func connectedController(_ engine: PerchPreviewEngine = PerchPreviewEngine(),
                         claude: WindowID = PerchPreviewEngine.Windows.claudeConversation) -> RelayController {
    let controller = freshController(engine)
    controller.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    controller.setup.connect(.claude, to: claude)
    controller.topic = "Pricing by seat or by usage"
    controller.summarize = { _ in
        try? await Task.sleep(for: .seconds(1.2))
        return "Whether to price by seat or by usage"
    }
    controller.summarizeReply = { reply in
        try? await Task.sleep(for: .seconds(1.5))
        return PerchPreviewEngine.gist(for: reply)
    }
    return controller
}

/// Every state the console shows, for the canvases below and the render
/// harness. A state that plays out, a run or its ending, sets itself going
/// and settles within a couple of seconds.
enum PerchPreviewState: CaseIterable {
    // Before a run.
    case severalWindows, bothConnected, noTopic, codeSession, stillReplying,
         chatgptClosed, claudeNotInstalled, longTopic,
         turnLimit, untilStopped, narrow
    // A side's tip.
    case tipConnected, tipChoosing, tipClosed, tipHeld
    // A run.
    case opening, running, runningUntilStopped, modelUnavailable, pausePending, paused,
         noteQueued, waitingForFocus, conversationCovered, held, handoffs
    // Its ending.
    case complete, stopped, turnLimitReached, interrupted, noteNotSent

    /// The canvas: the console in this state, standing as the panel does.
    @MainActor var scene: PerchPreviewScene {
        PerchPreviewScene(controller: controller(), consoleWidth: consoleWidth, tipSide: tipSide)
    }

    var consoleWidth: CGFloat { self == .narrow ? 600 : Perch.widgetWidth }

    var tipSide: Speaker? {
        switch self {
        case .tipConnected, .tipChoosing, .tipClosed: .chatgpt
        case .tipHeld: .claude
        default: nil
        }
    }

    @MainActor func controller() -> RelayController {
        switch self {
        case .severalWindows, .tipChoosing:
            // Two windows on each side, so neither is connected until one
            // is chosen from its line under the box.
            return freshController()
        case .bothConnected, .tipConnected:
            return connectedController()
        case .noTopic:
            let controller = connectedController()
            controller.topic = ""
            return controller
        case .codeSession:
            // Code as the mode under the prompt, with the bare model its
            // popup announces.
            return connectedController(claude: PerchPreviewEngine.Windows.claudeCode)
        case .stillReplying:
            // Claude is answering something the relay did not send, so
            // Start relay waits and the line under the box says why.
            return connectedController(PerchPreviewEngine(replying: .claude),
                                       claude: PerchPreviewEngine.Windows.claudeCode)
        case .chatgptClosed, .tipClosed:
            var closed = PerchPreviewEngine.bothReady
            closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
            return freshController(PerchPreviewEngine(readiness: closed))
        case .claudeNotInstalled:
            var missing = PerchPreviewEngine.bothReady
            missing.claude = SideStatus(appName: "Claude", state: .missing, headline: "Not running")
            return freshController(PerchPreviewEngine(readiness: missing,
                                                      installed: [.chatgpt: true, .claude: false]))
        case .longTopic:
            let controller = connectedController()
            controller.topic = Array(repeating: "Compare pricing by seat and by usage. Consider predictability, fairness, and how each option grows with a team.", count: 8)
                .joined(separator: "\n\n")
            return controller
        case .turnLimit:
            let controller = connectedController()
            controller.ending = .turnLimit
            controller.turns = 12
            return controller
        case .untilStopped:
            let controller = connectedController()
            controller.ending = .whenStopped
            return controller
        case .narrow:
            // Who starts and the arrangement fold into Run options; the
            // ending and its stepper stay on the row.
            let controller = connectedController()
            controller.ending = .turnLimit
            return controller
        case .tipHeld:
            return Self.held.controller()

        case .opening:
            // Just started: ChatGPT is writing the first reply, and the
            // summary is waiting for it.
            let controller = connectedController(PerchPreviewEngine(pace: .seconds(120)))
            controller.ending = .turnLimit
            controller.turns = 10
            controller.start()
            return controller
        case .running:
            // Turn 5 of 10, ChatGPT writing, with four replies and a note in
            // the summary.
            return Self.midRun { $0.ending = .turnLimit; $0.turns = 10 }
        case .runningUntilStopped:
            return Self.midRun(note: false) { $0.ending = .whenStopped }
        case .modelUnavailable:
            // No sentences come, so the topic line keeps saying who went
            // first and each summary line keeps its reply's opening.
            return Self.midRun {
                $0.summarize = { _ in nil }
                $0.summarizeReply = { _ in nil }
            }
        case .pausePending:
            // Pause to steer during the opening's delivery, which takes its
            // time here, so the field waits for it.
            let engine = PerchPreviewEngine(pace: .seconds(120), handoff: .seconds(3600),
                                            openingOperation: .delivery)
            let controller = connectedController(engine)
            controller.start()
            controller.beginSteering()
            return controller
        case .paused:
            // ChatGPT's fifth reply is ready to copy, so the pause holds at
            // once, and the note is written.
            let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5, atHandoff: true)
            let controller = connectedController(engine)
            controller.start()
            engine.postReplies(4, note: false)
            controller.beginSteering()
            controller.setSteeringText(PerchPreviewEngine.note)
            return controller
        case .noteQueued:
            // The note waits for the handoff after ChatGPT's reply, and its
            // echo for the one after that.
            let controller = Self.midRun(note: false)
            controller.beginSteering()
            controller.setSteeringText(PerchPreviewEngine.note)
            controller.sendSteering()
            return controller
        case .waitingForFocus:
            // Claude would not come to the front: the alert covers the
            // console until its window is clicked.
            return Self.midRun(blocked: .notInFront(side: .claude))
        case .conversationCovered:
            // An image is open in Claude's viewer, which hides the
            // conversation from Errol: the alert asks for it to be closed.
            return Self.midRun(blocked: .covered(side: .claude, by: "Image preview"))
        case .held:
            // Claude's window went to the Dock mid-run, and the run stands
            // until it comes back.
            return Self.midRun(blocked: .windowHidden(side: .claude, seen: "minimized"))
        case .handoffs:
            // Replies take two seconds and nobody signs off, so handoffs
            // play over and over until Stop.
            let controller = connectedController(PerchPreviewEngine(pace: .seconds(2.2)))
            controller.start()
            return controller

        case .complete:
            return Self.ended(.completed)
        case .stopped:
            return Self.ended(.stopped, replies: 4)
        case .turnLimitReached:
            return Self.ended(.turnLimitReached)
        case .interrupted:
            return Self.ended(.sendAbandoned(side: .claude), replies: 5)
        case .noteNotSent:
            // A note still waiting for its handoff when Stop ended the run:
            // on no line of the summary, so the panel keeps it.
            let controller = Self.midRun(note: false)
            controller.beginSteering()
            controller.setSteeringText(PerchPreviewEngine.note)
            controller.sendSteering()
            controller.stop()
            return Self.took(controller, 81)
        }
    }

    /// A run at turn 5, ChatGPT writing and taking its time, with four
    /// replies in the summary and, unless told otherwise, a note that rode
    /// the third handoff; standing on `blocked`, if given. `setUp` changes
    /// the controller before the start.
    @MainActor private static func midRun(note: Bool = true, blocked: RunBlock? = nil,
                                          _ setUp: (RelayController) -> Void = { _ in }) -> RelayController {
        let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
        let controller = connectedController(engine)
        setUp(controller)
        controller.start()
        engine.postReplies(4, note: note)
        if let blocked { engine.events.post(.blocked(blocked)) }
        return controller
    }

    /// A run that is already over, with the time a run like it takes.
    @MainActor private static func ended(_ outcome: RunOutcome, replies: Int = 6) -> RelayController {
        let controller = connectedController(.ended(outcome, replies: replies))
        controller.start()
        return took(controller, 81)
    }

    /// The summary's header reads the run's time once it is over, and a
    /// canvas's run ends in a moment; this gives it a real run's time.
    @MainActor private static func took(_ controller: RelayController, _ seconds: TimeInterval) -> RelayController {
        Task {
            var waited = 0
            while controller.stage != .finished, waited < 100 {
                try? await Task.sleep(for: .milliseconds(20))
                waited += 1
            }
            if controller.stage == .finished { controller.lastRunDuration = seconds }
        }
        return controller
    }
}

// The canvases themselves are in the files beside this one, one per group:
// PerchPreviews+Compose, +Participants, +Running, +Finished, and +Update.

#endif

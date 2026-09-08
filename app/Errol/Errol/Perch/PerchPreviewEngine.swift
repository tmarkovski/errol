// The canvases' engine: it plays a relay run without touching any app.
// The panel's controls do what they do in the app — Start starts a run,
// Stop ends it, Pause to steer holds it at the next handoff, Return sends a
// note that rides that handoff and is echoed at the next — and both apps
// read as ready throughout. The run's shape follows runRelay's: the same
// events in the same order, so the panel is exercised the way the real
// engine exercises it, only on a clock of seconds instead of minutes.

#if DEBUG
import Foundation

final class PerchPreviewEngine: RelayEngine {
    /// Its own bus and control, so several canvases in one preview process
    /// do not hear one another's runs, and the process-wide ones the real
    /// relay reads are never touched.
    let events = RelayEventBus()
    let control = RelayControl()
    /// Nothing sweeps; the picture is fixed and handed over as soon as the
    /// controller asks for it — a canvas never says the panel is visible.
    var onReadiness: ((SideStatus, SideStatus) -> Void)? {
        didSet { onReadiness?(readiness.chatgpt, readiness.claude) }
    }

    /// Both apps up with a chat open, the way the head likes to see them.
    static let bothReady = (
        chatgpt: SideStatus(appName: "ChatGPT", state: .ready, headline: "Ready",
                            surface: "Chat", model: "5.6 Sol High",
                            detail: "\u{201C}Pricing by seat or by usage\u{201D}"),
        claude: SideStatus(appName: "Claude", state: .ready, headline: "Ready",
                           surface: "Chat", model: "Fable 5 \u{00B7} Extra",
                           detail: "\u{201C}Pricing by seat or by usage\u{201D}")
    )

    private let readiness: (chatgpt: SideStatus, claude: SideStatus)
    private let replyTime: Duration
    private let signOffAt: Int?
    /// Where the first run stands when Start is pressed, for canvases that
    /// open mid-run. Runs started by hand after it start from the top.
    private var opening: (turn: Int, atHandoff: Bool)?
    private var run: Task<Void, Never>?
    private var openingOperation: FocusOperation?

    /// - Parameters:
    ///   - replyTime: How long each reply takes to write.
    ///   - turn: The turn the first run opens on. Who is writing it follows
    ///     from the first speaker, as in a run: odd turns are the opener's.
    ///   - atHandoff: Whether that turn's reply is already ready and the
    ///     run is at the capture boundary, so a pause asked for before the
    ///     canvas draws holds at once.
    ///   - signOffAt: The turn from which the agents sign off — the side
    ///     writing it ends the conversation, and the other closes out on
    ///     the next — the way a conversation ends on its own. nil means
    ///     the run goes on until the turn cap or Stop.
    ///   - openingOperation: Start inside capture or delivery so a pause made
    ///     immediately after Start exercises the pending editor state.
    ///   - readiness: What the perches show for the two apps.
    init(pace replyTime: Duration = .seconds(4),
         turn: Int = 1, atHandoff: Bool = false, signOffAt: Int? = nil,
         openingOperation: FocusOperation? = nil,
         readiness: (chatgpt: SideStatus, claude: SideStatus) = PerchPreviewEngine.bothReady) {
        self.replyTime = replyTime
        self.signOffAt = signOffAt
        self.readiness = readiness
        opening = (max(1, turn), atHandoff)
        self.openingOperation = openingOperation
    }

    deinit {
        run?.cancel()
    }

    func setScanning(_ scanning: Bool) {}

    func preflight() -> Bool { true }

    /// No windows to move; the chip hears the answer it would in the app.
    func setTiling(_ tiled: Bool) {
        events.post(.log(tiled ? "Preview: the chat windows would tile now."
                               : "Preview: the chat windows would go back now."))
        events.post(.arranged(tiled: tiled))
    }

    func startRun() {
        control.reset()
        run?.cancel()
        let opening = self.opening ?? (1, false)
        self.opening = nil
        let operation = openingOperation
        openingOperation = nil
        if let operation { _ = control.beginOperation(operation) }
        events.post(.log("Preview run: nothing is sent to either app."))
        let play = PreviewRun(events: events, control: control, replyTime: replyTime,
                              names: (readiness.chatgpt.appName, readiness.claude.appName),
                              first: config.first,
                              turnCap: config.limitTurns ? config.turns : nil,
                              signOffAt: signOffAt,
                              startTurn: opening.turn, atHandoff: opening.atHandoff,
                              openingOperation: operation)
        run = Task { await play.play() }
    }

    func inspect() {
        events.post(.log("Inspect reads both apps' Accessibility trees; a preview has none."))
    }
}

/// One played run. Off the engine, so a run in progress does not keep a
/// torn-down canvas's engine alive: cancelling the task ends the run, and
/// a cancelled run says nothing more. On the main actor, like the
/// controller that hears it, so a run cannot begin until the canvas that
/// started it has finished setting up — a pause asked for right after
/// Start is in place before the first handoff decision reads it.
@MainActor
private final class PreviewRun {
    private let events: RelayEventBus
    private let control: RelayControl
    private let replyTime: Duration
    private let names: (chatgpt: String, claude: String)
    private let first: Speaker
    private let turnCap: Int?
    private let signOffAt: Int?
    private let startTurn: Int
    private let atHandoff: Bool
    private var openingOperation: FocusOperation?
    private var operationActive: Bool

    private var chatgpt = ConversationStatus.notStarted
    private var claude = ConversationStatus.notStarted

    nonisolated init(events: RelayEventBus, control: RelayControl, replyTime: Duration,
                     names: (chatgpt: String, claude: String), first: Speaker, turnCap: Int?,
                     signOffAt: Int?, startTurn: Int, atHandoff: Bool,
                     openingOperation: FocusOperation?) {
        self.events = events
        self.control = control
        self.replyTime = replyTime
        self.names = names
        self.first = first
        self.turnCap = turnCap
        self.signOffAt = signOffAt
        self.startTurn = startTurn
        self.atHandoff = atHandoff
        self.openingOperation = openingOperation
        operationActive = openingOperation != nil
    }

    func play() async {
        defer {
            if operationActive { endOperation(continuing: false) }
            control.finishRun()
        }
        var speaker = startTurn % 2 == 1 ? first : other(than: first)
        var listener = other(than: speaker)
        set(speaker, .chatting)
        set(listener, .waiting)

        var turn = startTurn - 1
        var replyInHand = atHandoff
        var lastReplyEnded = false
        // A note travels twice: with the handoff it lands on, and echoed
        // with the next.
        var echo: (note: String, turn: Int)?

        while true {
            turn += 1
            events.post(.turn(turn))
            let reserved = openingOperation
            openingOperation = nil
            if replyInHand || reserved != nil {
                replyInHand = false
            } else if !(await writeReply()) {
                if Task.isCancelled { return }
                log("Run stopped by user.")
                break
            }

            set(speaker, .replied)
            if reserved != .delivery {
                var capture = reserved == .capture ? OperationDecision.proceed : control.beginOperation(.capture)
                if capture == .hold {
                    log("Paused — \(name(speaker))'s reply is ready; waiting to copy it.")
                    events.post(.holding(true))
                    repeat {
                        try? await Task.sleep(for: .milliseconds(200))
                        if Task.isCancelled { return }
                        capture = control.beginOperation(.capture)
                    } while capture == .hold
                    events.post(.holding(false))
                }
                guard capture == .proceed else { break }
                operationActive = true
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
            }

            let signedOff = signOffAt.map { turn >= $0 } ?? false
            if signedOff {
                set(speaker, .ended)
                if lastReplyEnded {
                    log("\(name(speaker)) ended the conversation too — both sides have signed off.")
                    break
                }
                log("\(name(speaker)) ended the conversation; relaying the sign-off so \(name(listener)) can close out.")
            }
            lastReplyEnded = signedOff

            log("Turn \(turn)\(turnCap.map { "/\($0)" } ?? ""): \(name(speaker)) -> \(name(listener))")
            if let turnCap, turn >= turnCap {
                log("Turn cap reached.")
                break
            }
            if reserved != .delivery { endOperation(continuing: true) }

            // The handoff boundary: hold, end, or go, as the control says.
            var decision = reserved == .delivery
                ? HandoffDecision.commit(note: nil, unfit: nil)
                : control.decideHandoff { _ in true }
            if decision == .hold {
                log("Paused — holding \(name(speaker))'s reply before it reaches \(name(listener)).")
                if !signedOff { set(speaker, .replied) }
                events.post(.holding(true))
                repeat {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                    decision = control.decideHandoff { _ in true }
                } while decision == .hold
                events.post(.holding(false))
                if decision != .cancel { log("Resumed.") }
            }
            guard case .commit(let note, _) = decision else {
                log("Run stopped by user.")
                break
            }
            operationActive = true

            if let note {
                log("Relaying the human's steering note with this handoff.")
                events.post(.steeringCommitted(note: note, recipient: listener, turn: turn))
            }
            // The paste and the send: a beat, so a committed note is seen
            // in flight before its receipt lands.
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            if let note {
                report(.note, note, to: listener, turn: turn, outcome: .delivered)
            }
            if let echo {
                report(.echo, echo.note, to: listener, turn: turn, outcome: .delivered)
            }
            echo = note.map { ($0, turn) }

            if !signedOff { set(speaker, .waiting) }
            set(listener, .chatting)
            endOperation(continuing: !control.isCancelled)
            if control.isCancelled { break }
            swap(&speaker, &listener)
        }

        if operationActive { endOperation(continuing: false) }
        control.finishRun()

        // What the run left undelivered, said outright, as the engine does.
        if let left = control.takeSteering() {
            report(.note, left, to: listener, turn: turn, outcome: .runEnded)
        }
        if let echo {
            report(.echo, echo.note, to: listener, turn: echo.turn + 1, outcome: .runEnded)
        }
        if chatgpt != .ended { set(.chatgpt, .notStarted) }
        if claude != .ended { set(.claude, .notStarted) }
        log("Done.")
        events.post(.finished)
    }

    private func endOperation(continuing: Bool) {
        completeFocusOperation(control: control, events: events, continuingRun: continuing)
        operationActive = false
    }

    /// The reply being written: replyTime on the clock, in slices, so Stop
    /// is seen within a moment of it. false when the run should end.
    private func writeReply() async -> Bool {
        let slice = Duration.milliseconds(200)
        var left = replyTime
        while left > .zero {
            if Task.isCancelled || control.isCancelled { return false }
            let step = min(slice, left)
            try? await Task.sleep(for: step)
            left -= step
        }
        return !Task.isCancelled && !control.isCancelled
    }

    private func set(_ side: Speaker, _ status: ConversationStatus) {
        switch side {
        case .chatgpt: chatgpt = status
        case .claude: claude = status
        }
        events.post(.conversation(chatgpt: chatgpt, claude: claude))
    }

    private func report(_ leg: SteeringDelivery.Leg, _ note: String, to recipient: Speaker,
                        turn: Int, outcome: SteeringOutcome) {
        events.post(.steering(SteeringDelivery(leg: leg, note: note, recipient: recipient,
                                               turn: turn, outcome: outcome)))
    }

    /// Timestamped like the engine's own lines (Logging.swift's `log`),
    /// on this run's bus rather than the process-wide one.
    private func log(_ line: String) {
        events.post(.log("[\(iso.string(from: Date()))] \(line)"))
    }

    private func name(_ side: Speaker) -> String {
        side == .chatgpt ? names.chatgpt : names.claude
    }

    private func other(than side: Speaker) -> Speaker {
        side == .chatgpt ? .claude : .chatgpt
    }
}
#endif

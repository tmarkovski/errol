// The canvases' engine: it plays a relay run without touching any app.
// The panel's controls do what they do in the app — Start starts a run,
// Stop ends it, Pause to steer holds it at the next handoff, Return sends a
// note that rides that handoff and is echoed at the next — and both apps
// read as ready throughout. The run's shape follows runRelay's: the same
// events in the same order, so the panel is exercised the way the real
// engine exercises it, only on a clock of seconds instead of minutes.
//
// Setup is played the same way: the apps' presence and windows are what
// the canvas says they are, a launch makes an app appear, a bind answers
// at once with the window's identity, and an arrangement moves nothing.

#if DEBUG
import CoreGraphics
import Foundation

final class PerchPreviewEngine: RelayEngine {
    /// Its own bus and control, so several canvases in one preview process
    /// do not hear one another's runs, and the process-wide ones the real
    /// relay reads are never touched.
    let events = RelayEventBus()
    let control = RelayControl()
    /// Nothing sweeps; the picture is fixed and handed over as soon as the
    /// controller asks for it — a canvas never says the panel is visible.
    var onReadiness: ((ReadinessReport) -> Void)? {
        didSet { publish() }
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

    /// What the agents say in a played run, one reply a turn from the
    /// first, round again once they run out, and the sentence the model
    /// would write on each (nil for a reply short enough to show whole). A
    /// canvas hands `gist(for:)` to the controller in the model's place.
    static let replies: [(text: String, gist: String?)] = [
        ("I'd lean toward per-seat pricing for the first year. Buyers can predict the bill, procurement understands it, and it maps to how the team already thinks about headcount. Usage pricing is fairer in theory, but it makes the first invoice a surprise, and surprises slow renewals. Where would you push back?",
         "Favors per-seat pricing because buyers can predict the bill"),
        ("Predictability matters, but seats punish exactly the customers you want: teams that roll the tool out widely and use it lightly. They'll share logins or cap seats, and you lose the network effect. I'd price by usage with a monthly cap, so the bill can't surprise anyone and wide adoption stays cheap.",
         "Holds that seats punish wide, light use and proposes capped usage pricing"),
        ("A cap helps, but it's still hard for a finance team to forecast. What about a hybrid: a small platform fee per seat, with usage above a generous included allowance? Seats give you the floor, and usage captures the heavy teams.",
         "Concedes the cap helps but proposes a per-seat floor plus usage"),
        ("The hybrid works if the allowance is generous enough that most teams never see an overage line. Otherwise you get the worst of both: seat friction and bill anxiety. I'd set the allowance at the 80th percentile of current usage and revisit it every quarter.",
         "Agrees with the hybrid if the allowance covers most teams"),
        ("Agreed on the 80th percentile. Let's draft the pricing page next.", nil),
        ("Here's a first pass. Headline: \u{201C}Pay for your team, not your curiosity.\u{201D} Then three tiers, each listing seats, the included allowance, and the overage rate, plus a calculator so buyers can check their own numbers before they ever talk to sales.",
         "Drafts pricing page copy with three tiers and a calculator"),
    ]

    static func reply(turn: Int) -> String {
        replies[(max(1, turn) - 1) % replies.count].text
    }

    static func gist(for reply: String) -> String? {
        let text = reply.replacingOccurrences(of: config.stopSequence, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return replies.first { $0.text == text }?.gist
    }

    /// The windows each app offers a canvas: the ids a preview connects by.
    enum Windows {
        static let chatgptConversation = WindowID(raw: 101)
        static let chatgptFresh = WindowID(raw: 102)
        static let claudeConversation = WindowID(raw: 201)
        static let claudeCode = WindowID(raw: 202)
    }

    private static func candidate(_ id: WindowID, title: String, composer: String,
                                  route: String? = nil, model: String? = nil,
                                  excluded: Bool = false, messages: Int, selectors: AppSelectors,
                                  frame: CGRect) -> WindowCandidate {
        var scan = WindowScan()
        scan.title = title
        scan.hasComposer = true
        scan.composerValue = composer
        scan.composerLabel = composer
        scan.conversationRoute = route
        scan.model = model
        scan.isExcluded = excluded
        scan.surfacePath = excluded ? "epitaxy" : nil
        scan.messageAffordances = messages
        var candidate = WindowCandidate(id: id, scan: scan, selectors: selectors, frame: frame)
        if candidate.identity.surface == nil { candidate.identity.surface = excluded ? "Code" : "Chat" }
        return candidate
    }

    static let chatgptWindows = [
        candidate(Windows.chatgptConversation, title: "Pricing by seat or by usage", composer: "\nMessage ChatGPT",
                  model: "5.6 Sol High", messages: 4, selectors: config.chatgptSelectors,
                  frame: CGRect(x: 0, y: 25, width: 720, height: 875)),
        candidate(Windows.chatgptFresh, title: "ChatGPT", composer: "\nMessage ChatGPT",
                  messages: 0, selectors: config.chatgptSelectors,
                  frame: CGRect(x: 60, y: 80, width: 720, height: 875)),
    ]
    static let claudeWindows = [
        candidate(Windows.claudeConversation, title: "Naming ideas", composer: "\n",
                  route: "/chat/8f3c2a91-77aa-4bfa-9f21-0d6e2b9d5c44", model: "Fable 5 \u{00B7} Extra",
                  messages: 6, selectors: config.claudeSelectors,
                  frame: CGRect(x: 720, y: 25, width: 720, height: 875)),
        candidate(Windows.claudeCode, title: "Claude", composer: "\n",
                  route: "/epitaxy/a1b2c3d4-5e6f-7089-9abc-def012345678", model: "Fable 5",
                  excluded: true, messages: 2, selectors: config.claudeSelectors,
                  frame: CGRect(x: 760, y: 80, width: 700, height: 800)),
    ]

    private var readiness: (chatgpt: SideStatus, claude: SideStatus)
    private var installed: [Speaker: Bool] = [.chatgpt: true, .claude: true]
    private var bindings: [Speaker: WindowCandidate] = [:]
    private var restorable = false
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
    ///   - readiness: What the perches show for the two apps. A side
    ///     reported missing offers no windows and can be "opened".
    ///   - installed: Whether each app is on this Mac at all.
    init(pace replyTime: Duration = .seconds(4),
         turn: Int = 1, atHandoff: Bool = false, signOffAt: Int? = nil,
         openingOperation: FocusOperation? = nil,
         readiness: (chatgpt: SideStatus, claude: SideStatus) = PerchPreviewEngine.bothReady,
         installed: [Speaker: Bool] = [.chatgpt: true, .claude: true]) {
        self.replyTime = replyTime
        self.signOffAt = signOffAt
        self.readiness = readiness
        self.installed = installed
        opening = (max(1, turn), atHandoff)
        self.openingOperation = openingOperation
    }

    deinit {
        run?.cancel()
    }

    // MARK: Readiness

    private func windows(_ side: Speaker) -> [WindowCandidate] {
        let status = side == .chatgpt ? readiness.chatgpt : readiness.claude
        guard status.state != .missing else { return [] }
        return side == .chatgpt ? Self.chatgptWindows : Self.claudeWindows
    }

    /// The fixed picture, as a sweep would report it.
    private func publish() {
        var report = ReadinessReport(chatgpt: readiness.chatgpt, claude: readiness.claude, installed: installed)
        for side in [Speaker.chatgpt, .claude] {
            report.candidates[side] = windows(side)
            if let bound = bindings[side] {
                report.bindings[side] = BindingObservation(check: .same, identity: bound.identity,
                                                           composer: bound.composer)
            }
        }
        onReadiness?(report)
    }

    func setScanning(_ scanning: Bool) {}

    func requestSweep() {
        publish()
    }

    // MARK: Setup

    func launch(_ side: Speaker) -> Bool {
        guard installed[side] ?? true else { return false }
        // The app "appears" a moment later, the way a launched one does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let ready = side == .chatgpt ? Self.bothReady.chatgpt : Self.bothReady.claude
            if side == .chatgpt { readiness.chatgpt = ready } else { readiness.claude = ready }
            publish()
        }
        return true
    }

    func bringForward(_ side: Speaker, completion: @escaping () -> Void) {
        events.post(.log("Preview: \(side == .chatgpt ? "ChatGPT" : "Claude") would come forward now."))
        DispatchQueue.main.async(execute: completion)
    }

    func bind(_ side: Speaker, to window: WindowID, completion: @escaping (BindingObservation?) -> Void) {
        guard let candidate = windows(side).first(where: { $0.id == window }) else {
            completion(nil)
            return
        }
        bindings[side] = candidate
        events.post(.log("Preview: \(side == .chatgpt ? "ChatGPT" : "Claude") connected to \(candidate.name)."))
        completion(BindingObservation(check: .same, identity: candidate.identity, composer: candidate.composer))
    }

    func unbind(_ side: Speaker) {
        bindings[side] = nil
    }

    func arrange(_ layout: LayoutChoice, windows: [Speaker: WindowID],
                 completion: @escaping (ArrangeOutcome) -> Void) {
        events.post(.log("Preview: the chat windows would be arranged \(layout.title.lowercased()) now."))
        restorable = layout.movesWindows
        completion(layout.movesWindows ? .arranged : .kept)
    }

    var canRestoreArrangement: Bool { restorable }

    func restoreArrangement(completion: @escaping (Int) -> Void) {
        events.post(.log("Preview: the chat windows would go back now."))
        let restored = restorable ? 2 : 0
        restorable = false
        completion(restored)
    }

    // MARK: Runs

    func preflight() -> Bool { true }

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
        var captured = max(0, startTurn - 1)
        var signedOffBy: Speaker?
        var outcome = RunOutcome.stopped
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
            captured += 1
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
            let reply = PerchPreviewEngine.reply(turn: turn)
            events.post(.reply(side: speaker, text: signedOff ? "\(reply)\n\n\(config.stopSequence)" : reply))
            if signedOff {
                set(speaker, .ended)
                if lastReplyEnded {
                    log("\(name(speaker)) ended the conversation too — both sides have signed off.")
                    signedOffBy = nil
                    outcome = .completed
                    break
                }
                signedOffBy = speaker
                log("\(name(speaker)) ended the conversation; relaying the sign-off so \(name(listener)) can close out.")
            }
            lastReplyEnded = signedOff

            log("Turn \(turn)\(turnCap.map { "/\($0)" } ?? ""): \(name(speaker)) -> \(name(listener))")
            if let turnCap, turn >= turnCap {
                log("Turn cap reached.")
                outcome = .turnLimitReached
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
        events.post(.ended(RunReport(outcome: outcome, repliesCaptured: captured, signedOffBy: signedOffBy)))
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

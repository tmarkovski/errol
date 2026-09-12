// The setup flow's state: where the human is in preparing a run, and what
// each side has been observed to be. Pure, so every transition runs in the
// tests with no app open (docs/design-proposals/setup-interaction/SPEC.md).
// The observable controller in the app wraps a SetupState and asks the
// engine for the observations; nothing here touches Accessibility, and the
// live window elements never enter it — a window is a WindowID here, and
// the engine keeps the element the id stands for.

import Foundation

// MARK: - Candidates

/// A window's identity for the length of the process. The engine keys its
/// registry of live elements on it; the pure state holds only the id.
struct WindowID: Hashable {
    let raw: UInt
}

/// One window of one app, as a place a conversation could be connected to:
/// what it shows and whether a run could target it.
struct WindowCandidate: Identifiable, Equatable {
    let id: WindowID
    var identity: DestinationIdentity
    var hasComposer: Bool
    var composer: ComposerState
    /// Model plus effort where the window announces one, as the strip
    /// renders it ("Fable 5 · Extra").
    var model: String?
    /// Messages visible in the window's tree, by their affordances. Zero
    /// under a generic title is the only evidence there is of a new chat.
    var visibleMessages: Int
    /// The window's frame in AX coordinates, for the picker's highlight;
    /// nil in fixtures.
    var frame: CGRect?
    var isMinimized: Bool
    /// Whether a run could target it: a composer in a chat window, or in an
    /// excluded-surface window where the selectors allow the fallback.
    let isEligible: Bool

    init(id: WindowID, scan: WindowScan, selectors: AppSelectors,
         frame: CGRect? = nil, isMinimized: Bool = false) {
        self.id = id
        identity = DestinationIdentity(scan: scan, selectors: selectors)
        hasComposer = scan.hasComposer
        composer = classifyComposer(value: scan.composerValue, label: scan.composerLabel,
                                    attachments: scan.attachmentChips, replying: scan.isReplying)
        model = scan.model
        if let effort = scan.effort {
            model = model.map { "\($0) \u{00B7} \(effort)" } ?? effort
        }
        visibleMessages = scan.messageAffordances
        self.frame = frame
        self.isMinimized = isMinimized
        isEligible = scan.hasComposer && (!scan.isExcluded || selectors.excludedSurfaceIsFallback)
    }

    /// How the window's conversation is named in the picker and under the
    /// icon: its title, its surface for a work session, or what can be said
    /// of an unnamed chat.
    var name: String {
        if !identity.titleIsGeneric { return "\u{201C}\(identity.title)\u{201D}" }
        if identity.excluded, let surface = identity.surface { return "\(surface) session" }
        return visibleMessages == 0 ? "New chat" : "Unnamed chat"
    }

    /// Whether the window continues an existing conversation or starts a
    /// new one, said only on evidence: a route or a title continues; an
    /// empty unnamed chat is new; anything else is left unnamed.
    var context: String {
        if identity.isDistinct { return "Continues here" }
        return visibleMessages == 0 ? "New chat" : "Unnamed chat"
    }

    /// The window's state as a place to paste into, one short phrase.
    var stateLine: String {
        if isMinimized { return "Minimized" }
        guard hasComposer else { return "No message field" }
        switch composer {
        case .empty: return "Ready"
        case .draft(let characters): return "Unsent draft (\(characters) characters)"
        case .attachments(let count): return count == 1 ? "Unsent attachment" : "\(count) unsent attachments"
        case .replying: return "Replying"
        case .unreadable: return "Message field can't be read"
        }
    }
}

/// The candidates one side's windows make, in the order a run would prefer
/// them: chat windows with a composer, then usable work sessions, then the
/// rest. Generic over the node so recorded trees produce the same list.
func windowCandidates<Node: ElementNode>(_ windows: [Node], ids: [WindowID],
                                          selectors: AppSelectors) -> [WindowCandidate] {
    windowCandidates(windows.map { scanWindow($0, selectors: selectors) }, ids: ids, selectors: selectors)
}

func windowCandidates(_ scans: [WindowScan], ids: [WindowID], selectors: AppSelectors) -> [WindowCandidate] {
    let candidates = zip(scans, ids).map { scan, id in
        WindowCandidate(id: id, scan: scan, selectors: selectors)
    }
    func rank(_ candidate: WindowCandidate) -> Int {
        guard candidate.isEligible else { return 2 }
        return candidate.identity.excluded ? 1 : 0
    }
    // A stable sort: the app's own window order holds within a rank.
    return candidates.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map(\.element)
}

// MARK: - Presence

/// What an app is, before any window in it is chosen: the state that names
/// the next useful action under its icon.
enum AppPresence: Equatable {
    case checking
    case notInstalled
    case notRunning
    /// Launch was asked for; the app has not been seen running yet.
    case launching
    /// Running, with no window at all.
    case noWindow
    /// Running, with windows, none of which a run could target.
    case noConversation
    /// Running with `windows` windows a run could target.
    case available(windows: Int)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Running, whatever its windows show: all the prepare step asks.
    var isOpen: Bool {
        switch self {
        case .noWindow, .noConversation, .available: return true
        case .checking, .notInstalled, .notRunning, .launching: return false
        }
    }

    /// The state under the app's name on the prepare step, which asks
    /// only that the app be open.
    var openState: String {
        switch self {
        case .checking: return "Checking\u{2026}"
        case .notInstalled: return "Not installed"
        case .notRunning: return "Click to open"
        case .launching: return "Opening\u{2026}"
        case .noWindow, .noConversation, .available: return "App open"
        }
    }

    /// The line under the icon: the next action, or the observed state.
    func action(name: String) -> String {
        switch self {
        case .checking: return "Checking\u{2026}"
        case .notInstalled: return "Not installed"
        case .notRunning: return "Open \(name)"
        case .launching: return "Opening\u{2026}"
        case .noWindow: return "Open a window"
        case .noConversation: return "Open a conversation"
        case .available: return "Ready"
        }
    }

    /// What keeps this side from being prepared, for the capsule's
    /// supporting line; nil when nothing does.
    func problem(name: String) -> String? {
        switch self {
        case .checking: return nil
        case .notInstalled:
            return "\(name) isn't installed on this Mac. Install it, then come back here."
        case .notRunning: return "\(name) isn't open."
        case .launching: return "Opening \(name)\u{2026}"
        case .noWindow: return "\(name) has no window open. Open one, then continue."
        case .noConversation:
            return "\(name) has no conversation to relay into. Open a chat in it, then continue."
        case .available: return nil
        }
    }
}

/// The presence a readiness sweep implies for a side.
func appPresence(installed: Bool, status: SideStatus, candidates: [WindowCandidate]) -> AppPresence {
    guard installed else { return .notInstalled }
    if status.state == .missing { return .notRunning }
    if candidates.isEmpty { return .noWindow }
    let eligible = candidates.filter(\.isEligible).count
    return eligible == 0 ? .noConversation : .available(windows: eligible)
}

// MARK: - A connection's readiness

/// How a connected side's bound conversation reads now — the same evidence
/// the run's preflight uses, so the setup UI and the click agree.
enum DestinationReadiness: Equatable {
    /// Connected but not observed since: a remembered destination, or a
    /// finished run's, until the next sweep reads it.
    case unverified
    case ready
    /// A work surface (a Claude Code session) waits for the deliberate
    /// choice to use it.
    case needsSurfaceChoice(String)
    /// The composer holds unsent work, or the app is replying, or the
    /// composer cannot be read: something to finish in the app first.
    case finishPreparing(RunBlock)
    /// The window no longer shows the connected conversation.
    case changed(String)
    /// The app quit or the window closed.
    case lost(String)

    var isReady: Bool { self == .ready }

    /// The word under the icon.
    func status(name: String) -> String {
        switch self {
        case .unverified: return "Last used"
        case .ready: return "Connected"
        case .needsSurfaceChoice: return "Needs a choice"
        case .finishPreparing: return "Finish preparing"
        case .changed: return "Changed"
        case .lost: return "Lost"
        }
    }

    /// Why sending is unavailable, beside the action; nil when it is not.
    func problem(name: String) -> String? {
        switch self {
        case .unverified: return "Checking \(name)'s conversation\u{2026}"
        case .ready: return nil
        case .needsSurfaceChoice(let surface):
            return "\(name) is showing a \(surface) session. Choose whether to use it."
        case .finishPreparing(let block): return block.startRefusal(name: name)
        case .changed(let seen):
            return "\(name) is \(seen). Show the connected conversation again, or choose another."
        case .lost(let detail):
            return "\(detail.prefix(1).uppercased())\(detail.dropFirst()). Connect \(name) again."
        }
    }
}

/// What a sweep read from a bound destination.
struct BindingObservation: Equatable {
    var check: BoundDestination.Check
    var identity: DestinationIdentity
    var composer: ComposerState
}

func destinationReadiness(_ observation: BindingObservation, side: Speaker,
                          surfaceAccepted: Bool) -> DestinationReadiness {
    switch observation.check {
    case .lost(let detail): return .lost(detail)
    case .changed(let seen): return .changed(seen)
    case .same: break
    }
    if observation.identity.excluded, !surfaceAccepted {
        return .needsSurfaceChoice(observation.identity.surface ?? "work")
    }
    if let block = deliveryBlock(for: observation.composer, side: side) {
        return .finishPreparing(block)
    }
    return .ready
}

// MARK: - Sides

/// One side's connection: the chosen window, the identity bound to it, and
/// how it reads now.
struct SideConnection: Equatable {
    var window: WindowID
    var identity: DestinationIdentity
    var model: String?
    var readiness = DestinationReadiness.unverified
    /// A work surface is used only after the deliberate choice.
    var surfaceAccepted = false
    /// The last observation, kept so accepting the surface can re-judge
    /// readiness without waiting for the next sweep.
    var lastObservation: BindingObservation?

    /// The conversation's name under the icon.
    var name: String {
        if !identity.titleIsGeneric { return "\u{201C}\(identity.title)\u{201D}" }
        if identity.excluded, let surface = identity.surface { return "\(surface) session" }
        return "New chat"
    }

    /// Continues or new, on the evidence at binding.
    var context: String { identity.isDistinct ? "Continues here" : "New chat" }
}

/// What was connected last time: a title and surface remembered across
/// launches, shown as "Last used" until a window showing them is observed
/// again. Never a live connection — an Accessibility element does not
/// survive the app it belongs to, let alone a relaunch of Errol.
struct DestinationHint: Equatable, Codable {
    var title: String?
    var surface: String?

    init?(identity: DestinationIdentity) {
        guard identity.isDistinct, !identity.titleIsGeneric else { return nil }
        title = identity.title
        surface = identity.surface
    }

    init(title: String?, surface: String?) {
        self.title = title
        self.surface = surface
    }

    var name: String {
        if let title { return "\u{201C}\(title)\u{201D}" }
        if let surface { return "the \(surface) conversation" }
        return "the last conversation"
    }

    func matches(_ candidate: WindowCandidate) -> Bool {
        guard let title, !candidate.identity.titleIsGeneric else { return false }
        return candidate.identity.title == title
    }
}

struct SideSetup: Equatable {
    let side: Speaker
    var presence = AppPresence.checking
    var candidates: [WindowCandidate] = []
    var connection: SideConnection?
    var hint: DestinationHint?
    /// The window chosen for arrangement when several could be moved and
    /// none is connected yet.
    var arrangementChoice: WindowID?

    var eligible: [WindowCandidate] { candidates.filter(\.isEligible) }
    var isConnected: Bool { connection != nil }
    var isReady: Bool { connection?.readiness.isReady ?? false }

    /// The window a layout moves: the connected one, else the one chosen
    /// for it, else the only one there is.
    var arrangementTarget: WindowID? {
        if let connection { return connection.window }
        if let choice = arrangementChoice, candidates.contains(where: { $0.id == choice }) { return choice }
        return eligible.count == 1 ? eligible[0].id : nil
    }

    /// Several windows could be moved and none has been named.
    var needsArrangementChoice: Bool { arrangementTarget == nil && eligible.count > 1 }

    /// The candidate the picker highlights first: the remembered one where
    /// a window still shows it, else the one a run would prefer.
    var preferredCandidate: WindowCandidate? {
        if let hint, let match = eligible.first(where: hint.matches) { return match }
        return eligible.first
    }
}

// MARK: - Steps and phases

/// The four guided steps, in the order the meter shows them: left to right,
/// ChatGPT before Claude whoever starts the conversation.
enum SetupStep: Int, CaseIterable, Comparable {
    case prepareApps, arrange, connectChatGPT, connectClaude

    static func < (lhs: SetupStep, rhs: SetupStep) -> Bool { lhs.rawValue < rhs.rawValue }

    static func connect(_ side: Speaker) -> SetupStep {
        side == .chatgpt ? .connectChatGPT : .connectClaude
    }

    var side: Speaker? {
        switch self {
        case .prepareApps, .arrange: return nil
        case .connectChatGPT: return .chatgpt
        case .connectClaude: return .claude
        }
    }

    func title(names: (chatgpt: String, claude: String)) -> String {
        switch self {
        case .prepareApps: return "Open the apps"
        case .arrange: return "Arrange the windows"
        case .connectChatGPT: return "Connect \(names.chatgpt)"
        case .connectClaude: return "Connect \(names.claude)"
        }
    }
}

enum SetupPhase: Equatable {
    case prepareApps
    case arrange
    case connect(Speaker)
    /// Both sides connected: the topic editor and the named Send.
    case compose

    var step: SetupStep? {
        switch self {
        case .prepareApps: return .prepareApps
        case .arrange: return .arrange
        case .connect(let side): return .connect(side)
        case .compose: return nil
        }
    }

    var isConnecting: Bool {
        if case .connect = self { return true }
        return false
    }
}

enum StepProgress: Equatable {
    case done, current, remaining
}

// MARK: - The state

struct SetupState: Equatable {
    var phase = SetupPhase.prepareApps
    var chatgpt = SideSetup(side: .chatgpt)
    var claude = SideSetup(side: .claude)
    var layout = LayoutChoice.keepPositions
    /// The chosen layout stands applied. Keep positions applies itself by
    /// being chosen; a moving layout is applied as soon as it is chosen,
    /// and stands applied once the engine says the windows took it.
    var layoutApplied = true
    /// Why the last arrangement did not happen, beside the action.
    var layoutProblem: String?
    var completed = Set<SetupStep>()
    /// The meter shows through the guided steps and on first reaching the
    /// editor; a run starting hides it, and the ordinary return keeps it
    /// hidden.
    var meterVisible = true

    subscript(side: Speaker) -> SideSetup {
        get { side == .chatgpt ? chatgpt : claude }
        set {
            if side == .chatgpt { chatgpt = newValue } else { claude = newValue }
        }
    }

    var currentStep: SetupStep? { phase.step }

    func progress(of step: SetupStep) -> StepProgress {
        if completed.contains(step) { return .done }
        return currentStep == step ? .current : .remaining
    }

    /// The meter's spoken value.
    func progressDescription(names: (chatgpt: String, claude: String)) -> String {
        guard let step = currentStep else { return "Setup complete: \(completed.count) of \(SetupStep.allCases.count) steps done" }
        return "Step \(step.rawValue + 1) of \(SetupStep.allCases.count): \(step.title(names: names))"
    }

    /// Both apps are running; the prepare step asks nothing of their windows.
    var bothOpen: Bool { chatgpt.presence.isOpen && claude.presence.isOpen }
    /// Both sides have a window a layout could move.
    var canArrange: Bool { chatgpt.arrangementTarget != nil && claude.arrangementTarget != nil }
    /// A side with several windows and none named, while the layout would
    /// move one; nothing to choose while nothing moves.
    func needsArrangementChoice(_ side: Speaker) -> Bool {
        layout.movesWindows && self[side].needsArrangementChoice
    }
    var bothConnected: Bool { chatgpt.isConnected && claude.isConnected }
    var bothReady: Bool { chatgpt.isReady && claude.isReady }

    /// The side whose connection is wanted first: ChatGPT before Claude.
    var firstUnconnected: Speaker? {
        if !chatgpt.isConnected { return .chatgpt }
        if !claude.isConnected { return .claude }
        return nil
    }

    /// Why Send is unavailable, or nil when both destinations are ready.
    func sendBlocker(names: (chatgpt: String, claude: String)) -> String? {
        guard phase == .compose else { return "Finish connecting both conversations first." }
        for side in [Speaker.chatgpt, .claude] {
            let name = side == .chatgpt ? names.chatgpt : names.claude
            guard let connection = self[side].connection else { return "Connect \(name) first." }
            if let problem = connection.readiness.problem(name: name) { return problem }
        }
        return nil
    }

    // MARK: Observations

    /// A sweep's word on a side's app and windows. A launch asked for
    /// stays "opening" until the app is seen running.
    mutating func observe(_ side: Speaker, presence: AppPresence, candidates: [WindowCandidate]) {
        var setup = self[side]
        switch (setup.presence, presence) {
        case (.launching, .notRunning), (.launching, .checking): break
        default: setup.presence = presence
        }
        setup.candidates = candidates
        self[side] = setup
    }

    /// A sweep's word on a side's bound conversation. A lost destination
    /// drops the connection: the side needs connecting again.
    mutating func observe(_ side: Speaker, binding: BindingObservation) {
        guard var connection = self[side].connection else { return }
        connection.identity = binding.identity
        connection.lastObservation = binding
        connection.readiness = destinationReadiness(binding, side: side,
                                                    surfaceAccepted: connection.surfaceAccepted)
        if case .lost = connection.readiness {
            disconnect(side)
            return
        }
        self[side].connection = connection
    }

    // MARK: Prepare

    mutating func launching(_ side: Speaker) {
        self[side].presence = .launching
    }

    mutating func launchFailed(_ side: Speaker, installed: Bool) {
        self[side].presence = installed ? .notRunning : .notInstalled
    }

    /// Going on is offered once both apps are open. Whether a window shows
    /// a conversation a run could target is the connect steps' concern.
    @discardableResult
    mutating func continueFromPrepare() -> Bool {
        guard phase == .prepareApps, bothOpen else { return false }
        completed.insert(.prepareApps)
        phase = .arrange
        return true
    }

    // MARK: Arrange

    /// Another layout. Keep positions is applied by the choice itself; a
    /// moving layout waits for the engine's word. The step's completion is
    /// untouched: it completes on Continue, and from the settings later
    /// the layout is a preference.
    mutating func choose(_ layout: LayoutChoice) {
        guard self.layout != layout else { return }
        self.layout = layout
        layoutProblem = nil
        layoutApplied = !layout.movesWindows
    }

    mutating func chooseArrangementWindow(_ side: Speaker, _ window: WindowID) {
        self[side].arrangementChoice = window
    }

    /// The engine's word on an arrangement. A layout that could not be
    /// made explains itself beside the action; a window gone is the next
    /// sweep's to report, and the layout applies again once there is a
    /// window to move. Either way the windows are as they are, and
    /// Continue stays offered.
    mutating func layoutOutcome(_ outcome: ArrangeOutcome) {
        switch outcome {
        case .arranged, .kept:
            layoutApplied = true
            layoutProblem = nil
        case .cannotFit(_, let reason):
            layoutApplied = false
            layoutProblem = reason + " Both windows stay where they were."
        case .windowMissing:
            layoutApplied = false
            layoutProblem = nil
        }
    }

    /// Continue is offered from the start: the windows are where the
    /// layout put them or where the human had them, and either is
    /// somewhere to go on from. The step completes here, not on the
    /// arrangement.
    @discardableResult
    mutating func continueFromArrange() -> Bool {
        guard phase == .arrange else { return false }
        completed.insert(.arrange)
        advanceToConnection()
        return true
    }

    // MARK: Connect

    /// The engine bound the chosen window: the step is done, and the flow
    /// moves to the other side or to the editor.
    mutating func connected(_ side: Speaker, window: WindowID, identity: DestinationIdentity,
                            model: String?, observation: BindingObservation) {
        var connection = SideConnection(window: window, identity: identity, model: model)
        connection.lastObservation = observation
        connection.readiness = destinationReadiness(observation, side: side, surfaceAccepted: false)
        self[side].connection = connection
        self[side].hint = DestinationHint(identity: identity) ?? self[side].hint
        completed.insert(.connect(side))
        if phase.isConnecting || phase == .compose { advanceToConnection() }
    }

    /// The deliberate choice to relay into a work session.
    mutating func acceptSurface(_ side: Speaker) {
        guard var connection = self[side].connection else { return }
        connection.surfaceAccepted = true
        if let observation = connection.lastObservation {
            connection.readiness = destinationReadiness(observation, side: side, surfaceAccepted: true)
        }
        self[side].connection = connection
    }

    /// Drop a side's connection: the side needs connecting again, and only
    /// that side — the other keeps its connection and the topic stays.
    mutating func disconnect(_ side: Speaker) {
        self[side].connection = nil
        completed.remove(.connect(side))
        switch phase {
        case .compose, .connect: phase = .connect(firstUnconnected ?? side)
        case .prepareApps, .arrange: break
        }
    }

    /// Set up fresh conversations: both sides are connected anew, the apps
    /// and the layout taken as they are.
    mutating func reconnectBoth() {
        chatgpt.connection = nil
        claude.connection = nil
        completed.subtract([.connectChatGPT, .connectClaude])
        phase = .connect(.chatgpt)
        meterVisible = true
    }

    /// Both connections stand to be verified again: a finished run's, on
    /// returning to the editor.
    mutating func markUnverified() {
        for side in [Speaker.chatgpt, .claude] {
            self[side].connection?.readiness = .unverified
        }
    }

    mutating func runStarted() {
        meterVisible = false
    }

    /// Guided setup from the top, with only the remembered destinations kept.
    mutating func restart() {
        let hints = (chatgpt.hint, claude.hint)
        self = SetupState()
        chatgpt.hint = hints.0
        claude.hint = hints.1
    }

    private mutating func advanceToConnection() {
        if let next = firstUnconnected {
            phase = .connect(next)
        } else {
            phase = .compose
        }
    }
}

// MARK: - Remembered destinations

/// The hints' home in the defaults, one per side.
enum DestinationHints {
    private static func key(_ side: Speaker) -> String { "lastDestination.\(side.rawValue)" }

    static func load(from defaults: UserDefaults = .standard) -> [Speaker: DestinationHint] {
        var hints: [Speaker: DestinationHint] = [:]
        for side in [Speaker.chatgpt, .claude] {
            if let data = defaults.data(forKey: key(side)),
               let hint = try? JSONDecoder().decode(DestinationHint.self, from: data) {
                hints[side] = hint
            }
        }
        return hints
    }

    static func save(_ hint: DestinationHint?, for side: Speaker, in defaults: UserDefaults = .standard) {
        guard let hint, let data = try? JSONEncoder().encode(hint) else {
            defaults.removeObject(forKey: key(side))
            return
        }
        defaults.set(data, forKey: key(side))
    }
}

// The console's setup state: what each side has been observed to be, which
// conversation it is connected to, and how the windows are arranged. Pure,
// so every transition runs in the tests with no app open. The observable
// controller in the app wraps a SetupState and asks the engine for the
// observations; nothing here touches Accessibility, and the live window
// elements never enter it — a window is a WindowID here, and the engine
// keeps the element the id stands for.

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
        composer = scan.coveredBy.map { .covered(by: $0) }
            ?? classifyComposer(value: scan.composerValue, label: scan.composerLabel,
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
        guard hasComposer || composer.isCovered else { return "No message field" }
        switch composer {
        case .empty: return "Ready"
        case .draft(let characters): return "Unsent draft (\(characters) characters)"
        case .attachments(let count): return count == 1 ? "Unsent attachment" : "\(count) unsent attachments"
        case .replying: return "Replying"
        case .unreadable: return "Message field can't be read"
        case .covered(let by): return by.isEmpty ? "Covered by a dialog" : "Covered by \u{201C}\(by)\u{201D}"
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
/// the next useful action on its line under the box.
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

    /// Running, whatever its windows show.
    var isOpen: Bool {
        switch self {
        case .noWindow, .noConversation, .available: return true
        case .checking, .notInstalled, .notRunning, .launching: return false
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
    /// The composer holds unsent work, or the app is replying, or the
    /// composer cannot be read: something to finish in the app first.
    case finishPreparing(RunBlock)
    /// The window is minimized: there, but out of reach.
    case hidden(String)
    /// The app quit or the window closed.
    case lost(String)

    var isReady: Bool { self == .ready }

    /// The word under the icon.
    func status(name: String) -> String {
        switch self {
        case .unverified: return "Last used"
        case .ready: return "Connected"
        case .finishPreparing: return "Finish preparing"
        case .hidden: return "Hidden"
        case .lost: return "Lost"
        }
    }

    /// Why sending is unavailable, beside the action; nil when it is not.
    func problem(name: String) -> String? {
        switch self {
        case .unverified: return "Checking \(name)'s conversation\u{2026}"
        case .ready: return nil
        case .finishPreparing(let block): return block.startRefusal(name: name)
        case .hidden(let seen):
            return "\(name)'s window is \(seen). Bring it back to send."
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

/// A work surface — a Claude Code session — reads like any other
/// conversation: the human chose that window, it is named as a Code
/// session under the icon, and the run's log says where everything lands.
func destinationReadiness(_ observation: BindingObservation, side: Speaker) -> DestinationReadiness {
    switch observation.check {
    case .lost(let detail): return .lost(detail)
    case .hidden(let seen): return .hidden(seen)
    case .same: break
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

    var eligible: [WindowCandidate] { candidates.filter(\.isEligible) }
    var isConnected: Bool { connection != nil }
    var isReady: Bool { connection?.readiness.isReady ?? false }
    /// Several windows could be connected and none has been named: the
    /// human chooses one from the side's line under the box.
    var needsConversationChoice: Bool { !isConnected && eligible.count > 1 }

    /// The connected window as the latest sweep saw it. The connection
    /// keeps what the window showed when it was made — the connection is
    /// the window, not the conversation in it — while this is what shows
    /// in it now: the surface tab, the model and its effort. nil until a
    /// sweep after the connection lists the window, and without one.
    var connectedCandidate: WindowCandidate? {
        guard let connection else { return nil }
        return candidates.first { $0.id == connection.window }
    }

    /// The window a layout moves: the connected one, else the only one
    /// there is.
    var arrangementTarget: WindowID? {
        if let connection { return connection.window }
        return eligible.count == 1 ? eligible[0].id : nil
    }
}

// MARK: - The state

struct SetupState: Equatable {
    var chatgpt = SideSetup(side: .chatgpt)
    var claude = SideSetup(side: .claude)
    var layout = LayoutChoice.keepPositions
    /// The chosen layout stands applied. Keep positions applies itself by
    /// being chosen; a moving layout is applied as soon as it is chosen,
    /// and stands applied once the engine says the windows took it.
    var layoutApplied = true
    /// Why the last arrangement did not happen, beside the action.
    var layoutProblem: String?

    subscript(side: Speaker) -> SideSetup {
        get { side == .chatgpt ? chatgpt : claude }
        set {
            if side == .chatgpt { chatgpt = newValue } else { claude = newValue }
        }
    }

    /// Both sides have a window a layout could move.
    var canArrange: Bool { chatgpt.arrangementTarget != nil && claude.arrangementTarget != nil }

    /// Why Send is unavailable, or nil when both destinations are ready.
    func sendBlocker(names: (chatgpt: String, claude: String)) -> String? {
        notice(names: names)?.text
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
        connection.readiness = destinationReadiness(binding, side: side)
        if case .lost = connection.readiness {
            disconnect(side)
            return
        }
        self[side].connection = connection
    }

    // MARK: The apps

    mutating func launching(_ side: Speaker) {
        self[side].presence = .launching
    }

    mutating func launchFailed(_ side: Speaker, installed: Bool) {
        self[side].presence = installed ? .notRunning : .notInstalled
    }

    // MARK: Arrange

    /// Another layout. Keep positions is applied by the choice itself; a
    /// moving layout waits for the engine's word.
    mutating func choose(_ layout: LayoutChoice) {
        guard self.layout != layout else { return }
        self.layout = layout
        layoutProblem = nil
        layoutApplied = !layout.movesWindows
    }

    /// The engine's word on an arrangement. A layout that could not be
    /// made explains itself beside the action; a window gone is the next
    /// sweep's to report, and the layout applies again once there is a
    /// window to move. Either way the windows are as they are.
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

    // MARK: Connect

    /// The window a side is connected to without being asked: the only one
    /// a run could target. With several, which one is the human's to say,
    /// and nothing is guessed from their order or from the last one used.
    func automaticConnection(for side: Speaker) -> WindowID? {
        guard !self[side].isConnected, self[side].eligible.count == 1 else { return nil }
        return self[side].eligible[0].id
    }

    /// Several windows could be connected and none has been named.
    func needsConversationChoice(_ side: Speaker) -> Bool {
        self[side].needsConversationChoice
    }

    /// The engine bound the chosen window.
    mutating func connected(_ side: Speaker, window: WindowID, identity: DestinationIdentity,
                            model: String?, observation: BindingObservation) {
        var connection = SideConnection(window: window, identity: identity, model: model)
        connection.readiness = destinationReadiness(observation, side: side)
        self[side].connection = connection
        self[side].hint = DestinationHint(identity: identity) ?? self[side].hint
    }

    /// Drop a side's connection: the side needs connecting again, and only
    /// that side — the other keeps its connection and the topic stays.
    mutating func disconnect(_ side: Speaker) {
        self[side].connection = nil
    }

    /// Both connections stand to be verified again: a finished run's, on
    /// returning to the editor.
    mutating func markUnverified() {
        for side in [Speaker.chatgpt, .claude] {
            self[side].connection?.readiness = .unverified
        }
    }

    // MARK: The notice

    /// What stands between the console and Send, the first thing first: an
    /// app missing, the apps closed, then each side's windows and its
    /// connection, ChatGPT before Claude. Nil when both destinations read
    /// ready. A wait is not a problem; something the human must fix is.
    func notice(names: (chatgpt: String, claude: String)) -> SetupNotice? {
        let sides = [Speaker.chatgpt, .claude]
        func name(_ side: Speaker) -> String { side == .chatgpt ? names.chatgpt : names.claude }

        if let missing = sides.first(where: { self[$0].presence == .notInstalled }) {
            return SetupNotice(text: "\(name(missing)) isn't installed on this Mac. Install it, then come back here.",
                               isProblem: true)
        }
        let closed = sides.filter { self[$0].presence == .notRunning }
        if !closed.isEmpty {
            return SetupNotice(text: "Open \(closed.map(name).joined(separator: " and ")) to begin.",
                               isProblem: false)
        }
        for side in sides {
            let setup = self[side]
            if let connection = setup.connection {
                guard let problem = connection.readiness.problem(name: name(side)) else { continue }
                return SetupNotice(text: problem, isProblem: connection.readiness != .unverified)
            }
            switch setup.presence {
            case .checking:
                return SetupNotice(text: "Checking \(name(side))\u{2026}", isProblem: false)
            case .launching:
                return SetupNotice(text: "Opening \(name(side))\u{2026}", isProblem: false)
            case .noWindow:
                return SetupNotice(text: "\(name(side)) has no window open. Open a chat in it.", isProblem: false)
            case .noConversation:
                return SetupNotice(text: "\(name(side)) has no conversation to relay into. Open a chat in it.",
                                   isProblem: false)
            case .available(let windows) where windows > 1:
                return SetupNotice(text: "\(name(side)) has \(windows) conversations open. Click the line below to choose one.",
                                   isProblem: false)
            case .available, .notInstalled, .notRunning:
                return SetupNotice(text: "Connecting \(name(side))\u{2026}", isProblem: false)
            }
        }
        return nil
    }
}

/// The line above the prompt: the next thing a side needs, or what is
/// wrong with it.
struct SetupNotice: Equatable {
    var text: String
    var isProblem: Bool
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

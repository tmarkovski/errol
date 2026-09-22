// The setup's observable face: the pure SetupState (Core/Setup.swift)
// driven by the engine's readiness sweeps and the human's actions, plus
// the remembered destinations in the defaults. Main thread only; the
// engine answers on the main thread.
//
// Connecting has one entry point, `connect(_:to:)`. A side with one window
// a run could target is connected to it as a sweep sees it; a side with
// several waits for the human to choose one from its icon. Both come
// through `connect(_:to:)`.

import AppKit
import Foundation
import Observation

@Observable
final class SetupController {
    private(set) var state: SetupState
    /// Told each time a layout has moved the windows. Arranging brings each
    /// chat app forward so the pair is the visible one (WindowArranger
    /// .apply), which leaves the keyboard with whichever app came forward
    /// last; the shell takes it back for the console. Main thread.
    @ObservationIgnored var onArranged: (() -> Void)?
    /// Told each time an app has been brought forward from its icon, which
    /// leaves the keyboard with that app; the shell takes it back for the
    /// console. Main thread.
    @ObservationIgnored var onBroughtForward: (() -> Void)?
    /// A bind is on the worker: a second Return or click waits for it.
    private(set) var isBinding = false
    /// An arrangement is on the worker.
    private(set) var isArranging = false
    /// Why the last connect or arrangement did not happen, beside the action.
    private(set) var problem: String?
    /// The apps' names as the panel shows them.
    var names: (chatgpt: String, claude: String) = ("ChatGPT", "Claude")

    @ObservationIgnored private let engine: RelayEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var launchDeadlines: [Speaker: Timer] = [:]
    @ObservationIgnored private var arrangementsInFlight = 0
    /// The windows the last arrangement was asked to move, so a sweep
    /// applies a moving layout only to windows it has not tried.
    @ObservationIgnored private var arrangedTargets: [Speaker: WindowID]?
    /// A window the console tried to connect on its own and could not, so
    /// the next sweep does not try the same one again.
    @ObservationIgnored private var refusedAutomatically: [Speaker: WindowID] = [:]
    /// A run owns the bound windows. One that loses its window ends saying
    /// so; it is never handed another window in the meantime.
    @ObservationIgnored private var runInProgress = false

    init(engine: RelayEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        var state = SetupState()
        for (side, hint) in DestinationHints.load(from: defaults) { state[side].hint = hint }
        self.state = state
    }

    func name(_ side: Speaker) -> String {
        side == .chatgpt ? names.chatgpt : names.claude
    }

    var canRestoreLayout: Bool { engine.canRestoreArrangement }

    /// The line above the prompt: why the last action did not happen, then
    /// what the sides still need.
    var notice: SetupNotice? {
        if let problem = problem ?? state.layoutProblem { return SetupNotice(text: problem, isProblem: true) }
        return state.notice(names: names)
    }

    // MARK: Observations

    /// Each sweep's word on the apps, their windows, and the bindings.
    func apply(_ report: ReadinessReport) {
        for side in [Speaker.chatgpt, .claude] {
            let status = side == .chatgpt ? report.chatgpt : report.claude
            let candidates = report.candidates[side] ?? []
            let presence = appPresence(installed: report.installed[side] ?? true,
                                       status: status, candidates: candidates)
            state.observe(side, presence: presence, candidates: candidates)
            if presence != .launching, presence != .notRunning { clearLaunchDeadline(side) }
            if let binding = report.bindings[side] {
                state.observe(side, binding: binding)
            }
            // A connection the state dropped — the window closed, the app
            // quit — leaves nothing for the engine to keep checking.
            if state[side].connection == nil, report.bindings[side] != nil, !isBinding {
                engine.unbind(side)
            }
        }
        applyIfPending()
        connectIfUnambiguous()
    }

    // MARK: The apps

    func launch(_ side: Speaker) {
        guard engine.launch(side) else {
            state.launchFailed(side, installed: false)
            return
        }
        state.launching(side)
        launchDeadlines[side]?.invalidate()
        // An app that never shows up goes back to "Open": a launch that
        // failed silently should not read as opening forever.
        launchDeadlines[side] = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self, state[side].presence == .launching else { return }
            state.launchFailed(side, installed: true)
        }
    }

    /// Open whichever app is not open.
    func launchBoth() {
        for side in [Speaker.chatgpt, .claude] where state[side].presence == .notRunning {
            launch(side)
        }
    }

    /// Bring the app forward — its connected window, where it has one —
    /// so the conversation is in view, and hand the keyboard back to the
    /// console once it is there.
    func bringForward(_ side: Speaker) {
        engine.bringForward(side) { [weak self] in self?.onBroughtForward?() }
    }

    private func clearLaunchDeadline(_ side: Speaker) {
        launchDeadlines[side]?.invalidate()
        launchDeadlines[side] = nil
    }

    // MARK: Arrange

    /// The layout as chosen, from the control beside the prompt: the
    /// choice applies at once — the windows move, or stay.
    func choose(_ layout: LayoutChoice) {
        guard state.layout != layout else { return }
        problem = nil
        state.choose(layout)
        applyIfChosen()
        if layout == .keepPositions { announce(layout.outcomeMessage) }
    }

    private func applyIfChosen() {
        guard state.layout.movesWindows, state.canArrange else { return }
        applyLayout()
    }

    /// A moving layout chosen while a side had no window to move — none
    /// open, or several and none connected, or the one asked for gone —
    /// applies once a sweep offers windows it has not tried: the choice
    /// stands. A layout that would not fit is not tried again on its own.
    private func applyIfPending() {
        guard state.layout.movesWindows, state.layoutProblem == nil,
              !isArranging, let targets = arrangementTargets, targets != arrangedTargets else { return }
        applyLayout()
    }

    private var arrangementTargets: [Speaker: WindowID]? {
        guard let chatgpt = state.chatgpt.arrangementTarget,
              let claude = state.claude.arrangementTarget else { return nil }
        return [.chatgpt: chatgpt, .claude: claude]
    }

    /// Apply the chosen layout to the two windows. Keep positions applies
    /// itself; the others need a window on each side.
    func applyLayout() {
        problem = nil
        guard state.layout.movesWindows else {
            state.layoutOutcome(.kept)
            return
        }
        guard let chatgpt = state.chatgpt.arrangementTarget else {
            problem = missingWindowProblem(.chatgpt)
            return
        }
        guard let claude = state.claude.arrangementTarget else {
            problem = missingWindowProblem(.claude)
            return
        }
        let layout = state.layout
        let windows: [Speaker: WindowID] = [.chatgpt: chatgpt, .claude: claude]
        arrangedTargets = windows
        arrangementsInFlight += 1
        isArranging = true
        engine.arrange(layout, windows: windows) { [weak self] outcome in
            guard let self else { return }
            arrangementsInFlight -= 1
            isArranging = arrangementsInFlight > 0
            // Whatever the choice is now, the windows moved and the apps
            // came forward.
            if outcome == .arranged { onArranged?() }
            // The word on a layout no longer chosen says nothing about the
            // one that is.
            guard state.layout == layout else { return }
            state.layoutOutcome(outcome)
            announce(state.layoutProblem ?? (state.layoutApplied ? layout.outcomeMessage
                : "A window is no longer available. Continue as they are, or choose another window."))
        }
    }

    private func missingWindowProblem(_ side: Speaker) -> String {
        state[side].needsConversationChoice
            ? "Choose which \(name(side)) conversation to connect: click its icon."
            : "Open a conversation in \(name(side)) first."
    }

    /// Put the arranged windows back where they were.
    func restoreLayout() {
        engine.restoreArrangement { [weak self] restored in
            guard let self else { return }
            if restored == 0 { problem = "Nothing to put back: the windows were moved since, or are gone." }
        }
    }

    // MARK: Connect

    /// The one way a side gets connected. The engine binds the window on
    /// its worker and answers with what it read; the state takes the
    /// connection from there.
    func connect(_ side: Speaker, to window: WindowID) {
        guard !isBinding else { return }
        isBinding = true
        problem = nil
        let candidate = state[side].candidates.first { $0.id == window }
        engine.bind(side, to: window) { [weak self] observation in
            guard let self else { return }
            isBinding = false
            guard let observation else {
                refusedAutomatically[side] = window
                problem = "That \(name(side)) window is gone. Choose another."
                engine.requestSweep()
                return
            }
            refusedAutomatically[side] = nil
            state.connected(side, window: window, identity: observation.identity,
                            model: candidate?.model, observation: observation)
            DestinationHints.save(state[side].hint, for: side, in: defaults)
            announce("\(name(side)) connected to \(state[side].connection?.name ?? "its conversation").")
            // One bind at a time: the other side's turn comes now, not a
            // sweep later.
            connectIfUnambiguous()
        }
    }

    /// A side whose app shows one window a run could target is connected
    /// to it, here, when a sweep first sees it, and the binding is held
    /// from then on. Nothing is searched for at Send, and a side with
    /// several windows is never chosen for (SetupState.automaticConnection).
    private func connectIfUnambiguous() {
        guard !runInProgress, !isBinding else { return }
        for side in [Speaker.chatgpt, .claude] {
            guard let window = state.automaticConnection(for: side),
                  refusedAutomatically[side] != window else { continue }
            connect(side, to: window)
            return
        }
    }

    /// Choose another conversation for a connected side: the connection is
    /// dropped, and the side is connected again the way any side is.
    func chooseAnother(_ side: Speaker) {
        problem = nil
        engine.unbind(side)
        state.disconnect(side)
        engine.requestSweep()
    }

    // MARK: Runs and returns

    func runStarted() {
        problem = nil
        runInProgress = true
    }

    func runEnded() {
        runInProgress = false
    }

    /// Another topic in these conversations: both are verified again
    /// before Send is offered.
    func revalidate() {
        problem = nil
        state.markUnverified()
        engine.requestSweep()
    }

    private func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

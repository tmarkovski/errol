// The setup flow's observable face: the pure SetupState (Core/Setup.swift)
// driven by the engine's readiness sweeps and the human's actions, plus the
// two things that are the app's rather than the state's — the window
// picker, with its keyboard and its highlight over the candidate, and the
// remembered destinations in the defaults. Main thread only; the engine
// answers on the main thread.
//
// Connecting has one entry point, `connect(_:to:)`, whatever the gesture:
// the picker's Return or click, or a drop from the icon onto the area
// drawn over a window's message field. Both produce the same binding and
// the same connected state.

import AppKit
import Foundation
import Observation

/// A side's window being chosen: the candidates as the last sweep offered
/// them, and the one the arrow keys stand on.
struct WindowPicker: Equatable {
    let side: Speaker
    var candidates: [WindowCandidate]
    var highlighted: Int

    var current: WindowCandidate? {
        candidates.indices.contains(highlighted) ? candidates[highlighted] : nil
    }
}

@Observable
final class SetupController {
    private(set) var state: SetupState
    private(set) var picker: WindowPicker?
    private(set) var draggingSide: Speaker?
    /// The window under the dragged icon: the one whose area is armed.
    private(set) var dragCandidate: WindowCandidate?
    /// The areas drawn for the drag, once the engine has brought the app
    /// forward and read them; nil while it is being asked.
    private(set) var dropZones: [ConnectionDropZone]?
    /// A bind is on the worker: a second Return or click waits for it.
    private(set) var isBinding = false
    /// An arrangement is on the worker: Continue waits for its outcome, so
    /// a move that fails is seen on the step it belongs to.
    private(set) var isArranging = false
    /// Why the last connect or arrangement did not happen, beside the action.
    private(set) var problem: String?
    /// The apps' names as the panel shows them.
    var names: (chatgpt: String, claude: String) = ("ChatGPT", "Claude")

    @ObservationIgnored private let engine: RelayEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let highlight = WindowHighlight()
    @ObservationIgnored private var launchDeadlines: [Speaker: Timer] = [:]
    @ObservationIgnored private var arrangementsInFlight = 0
    /// The windows the last arrangement was asked to move, so a sweep
    /// applies a moving layout only to windows it has not tried.
    @ObservationIgnored private var arrangedTargets: [Speaker: WindowID]?
    @ObservationIgnored private let dropOverlay = ConnectionDropOverlay()
    @ObservationIgnored private var dragGeneration = UUID()
    @ObservationIgnored private var dragPoint: CGPoint?
    @ObservationIgnored private var dragOverConsole = false
    /// Where the icon was released while the areas were still being read.
    @ObservationIgnored private var dropPoint: CGPoint?

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

    /// Whether the guided screens are showing, as against the editor.
    var isGuiding: Bool { state.phase != .compose }

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
        if var picker {
            // The picker follows the sweep, keeping its place on the same
            // window where it is still offered.
            let current = picker.current?.id
            picker.candidates = state[picker.side].candidates
            if let current, let index = picker.candidates.firstIndex(where: { $0.id == current }) {
                picker.highlighted = index
            } else {
                picker.highlighted = min(picker.highlighted, max(0, picker.candidates.count - 1))
            }
            self.picker = picker
            updateHighlight()
        }
    }

    // MARK: Prepare the apps

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

    /// Open whichever app is not open: the step's one action until both are.
    func launchBoth() {
        for side in [Speaker.chatgpt, .claude] where state[side].presence == .notRunning {
            launch(side)
        }
    }

    /// Bring the app forward so a conversation can be opened in it.
    func openConversation(_ side: Speaker) {
        engine.bringForward(side)
    }

    func continueFromPrepare() {
        problem = nil
        state.continueFromPrepare()
    }

    private func clearLaunchDeadline(_ side: Speaker) {
        launchDeadlines[side]?.invalidate()
        launchDeadlines[side] = nil
    }

    // MARK: Arrange

    /// The layout as chosen. On the arrange step the choice applies at
    /// once — the windows move, or stay — and Continue is there throughout;
    /// from the settings later it is a preference, applied by its own
    /// command.
    func choose(_ layout: LayoutChoice) {
        guard state.layout != layout else { return }
        problem = nil
        state.choose(layout)
        applyIfChosen()
        if layout == .keepPositions { announce(layout.completionMessage) }
    }

    /// The window to move, where a side has several: once named, the
    /// chosen layout applies.
    func chooseArrangementWindow(_ side: Speaker, _ window: WindowID) {
        state.chooseArrangementWindow(side, window)
        applyIfChosen()
    }

    private func applyIfChosen() {
        guard state.phase == .arrange, state.layout.movesWindows, state.canArrange else { return }
        applyLayout()
    }

    /// A moving layout chosen while a side had no window to move — none
    /// open, or several and none named, or the one asked for gone —
    /// applies once a sweep offers windows it has not tried: the choice
    /// stands, and the step has no other way to say "now". A layout that
    /// would not fit is not tried again on its own.
    private func applyIfPending() {
        guard state.phase == .arrange, state.layout.movesWindows, state.layoutProblem == nil,
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
            problem = state.chatgpt.needsArrangementChoice
                ? "Choose which \(names.chatgpt) window to move: click its icon."
                : "Open a conversation in \(names.chatgpt) first."
            return
        }
        guard let claude = state.claude.arrangementTarget else {
            problem = state.claude.needsArrangementChoice
                ? "Choose which \(names.claude) window to move: click its icon."
                : "Open a conversation in \(names.claude) first."
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
            // The word on a layout no longer chosen says nothing about the
            // one that is.
            guard state.layout == layout else { return }
            state.layoutOutcome(outcome)
            announce(state.layoutProblem ?? (state.layoutApplied ? layout.completionMessage
                : "A window is no longer available. Continue as they are, or choose another window."))
        }
    }

    /// Put the arranged windows back where they were.
    func restoreLayout() {
        engine.restoreArrangement { [weak self] restored in
            guard let self else { return }
            if restored == 0 { problem = "Nothing to put back: the windows were moved since, or are gone." }
        }
    }

    func continueFromArrange() {
        guard !isArranging else { return }
        problem = nil
        state.continueFromArrange()
    }

    // MARK: Connect

    /// The drag from the icon, whose frame `icon` is (AX coordinates): a
    /// lead runs out of it to the pointer from the first move. Errol tracks
    /// the pointer itself, so no file drag reaches the destination app. The
    /// engine brings the app forward under the console and answers with an
    /// area over each of its message fields, drawn as soon as it does; the
    /// drop resolves against those areas as drawn — the pointer over one
    /// arms it, releasing there connects its window — never against
    /// whatever window happens to be under the pointer.
    func beginDragging(_ side: Speaker, from icon: CGRect) {
        guard !isBinding, state.phase == .connect(side) else { return }
        cancelPicking()
        problem = nil
        dragGeneration = UUID()
        let generation = dragGeneration
        draggingSide = side
        dragCandidate = nil
        dropZones = nil
        dragPoint = nil
        dragOverConsole = false
        dropPoint = nil
        dropOverlay.beginLead(from: icon)
        let windows = state[side].candidates.filter { $0.isEligible && !$0.isMinimized }.map(\.id)
        engine.connectionDropZones(for: side, windows: windows) { [weak self] zones in
            guard let self, generation == dragGeneration, draggingSide == side else { return }
            dropZones = zones
            dropOverlay.show(zones.map { self.dropArea($0, side: side) })
            if let point = dropPoint {
                finishDrop(at: point)
            } else if let point = dragPoint {
                updateDrag(at: point, overConsole: dragOverConsole)
            }
        }
    }

    /// The pointer moved (AX coordinates): the area under it, if any, is
    /// armed. Over the console — the pointer back where it started —
    /// nothing is, whatever the console covers.
    func updateDrag(at point: CGPoint, overConsole: Bool = false) {
        guard let side = draggingSide, dropPoint == nil else { return }
        dragPoint = point
        dragOverConsole = overConsole
        dropOverlay.moveLead(to: point)
        guard let zones = dropZones else { return }
        let zone = overConsole ? nil : dropZone(at: point, among: zones)
        let candidate = zone.flatMap { zone in state[side].candidates.first { $0.id == zone.window } }
        guard candidate?.id != dragCandidate?.id else { return }
        dragCandidate = candidate
        dropOverlay.arm(candidate?.id)
    }

    /// The release. Over the console it is the icon put back: nothing
    /// happens and nothing is said. Elsewhere the drop resolves against
    /// the areas — once they arrive, if the drag was quicker than the app
    /// coming forward.
    func endDragging(at point: CGPoint, overConsole: Bool = false) {
        guard draggingSide != nil else { return }
        if overConsole {
            cancelDragging()
            return
        }
        dropPoint = point
        if dropZones != nil { finishDrop(at: point) }
    }

    private func finishDrop(at point: CGPoint) {
        guard let side = draggingSide, let zones = dropZones else { return }
        let zone = dropZone(at: point, among: zones)
        cancelDragging()
        if let zone {
            connect(side, to: zone.window)
            return
        }
        problem = zones.isEmpty
            ? "No \(name(side)) conversation is showing. Open a chat in it and drag again, or click to choose a window."
            : "Drop onto the marked message field in \(name(side)), or click to choose a window."
        announce(problem!)
    }

    func cancelDragging() {
        dragGeneration = UUID()
        draggingSide = nil
        dragCandidate = nil
        dropZones = nil
        dragPoint = nil
        dragOverConsole = false
        dropPoint = nil
        dropOverlay.hide()
    }

    /// The words on an area: the invitation, and what releasing there does.
    private func dropArea(_ zone: ConnectionDropZone, side: Speaker) -> ConnectionDropArea {
        let candidate = state[side].candidates.first { $0.id == zone.window }
        return ConnectionDropArea(
            zone: zone,
            invitation: "Drop here",
            explanation: zone.marksPrompt ? "Errol pastes messages here and sends them"
                                          : "Errol writes into this window's message field",
            armedHeadline: "Release to connect",
            armedDetail: candidate.map { "\($0.name) \u{00B7} \($0.stateLine)" } ?? name(side))
    }

    /// Open the picker for `side`: the candidates as last swept, the
    /// remembered window highlighted first.
    func beginPicking(_ side: Speaker) {
        guard !isBinding else { return }
        cancelDragging()
        problem = nil
        let setup = state[side]
        engine.requestSweep()
        guard !setup.candidates.isEmpty else {
            problem = "\(name(side)) has no window to connect. Open a conversation in it first."
            return
        }
        let first = setup.preferredCandidate.flatMap { preferred in
            setup.candidates.firstIndex(where: { $0.id == preferred.id })
        } ?? 0
        picker = WindowPicker(side: side, candidates: setup.candidates, highlighted: first)
        updateHighlight()
    }

    func movePick(by delta: Int) {
        guard var picker, !picker.candidates.isEmpty else { return }
        picker.highlighted = (picker.highlighted + delta + picker.candidates.count) % picker.candidates.count
        self.picker = picker
        updateHighlight()
    }

    /// Stand on a candidate: the pointer resting on its row.
    func highlightPick(_ id: WindowID) {
        guard var picker, let index = picker.candidates.firstIndex(where: { $0.id == id }),
              index != picker.highlighted else { return }
        picker.highlighted = index
        self.picker = picker
        updateHighlight()
    }

    /// Return, or a click on the highlighted row: connect the window it
    /// stands on, if a run could target it.
    func choosePick() {
        guard let picker, let candidate = picker.current else { return }
        guard candidate.isEligible, !candidate.isMinimized else {
            problem = candidate.hasComposer
                ? "That window is minimized. Bring it back, or choose another."
                : "That window has no message field to relay into. Choose another."
            return
        }
        connect(picker.side, to: candidate.id)
    }

    func cancelPicking() {
        cancelDragging()
        picker = nil
        highlight.hide()
    }

    /// The one way a side gets connected, whatever gesture chose the
    /// window. The engine binds it on its worker and answers with what it
    /// read; the state takes the connection from there.
    func connect(_ side: Speaker, to window: WindowID) {
        guard !isBinding else { return }
        cancelDragging()
        isBinding = true
        problem = nil
        let candidate = state[side].candidates.first { $0.id == window }
        picker = nil
        highlight.hide()
        engine.bind(side, to: window) { [weak self] observation in
            guard let self else { return }
            isBinding = false
            guard let observation else {
                problem = "That \(name(side)) window is gone. Choose another."
                engine.requestSweep()
                return
            }
            state.connected(side, window: window, identity: observation.identity,
                            model: candidate?.model, observation: observation)
            DestinationHints.save(state[side].hint, for: side, in: defaults)
            announce("\(name(side)) connected to \(state[side].connection?.name ?? "its conversation").")
        }
    }

    /// The deliberate choice to relay into a work session.
    func acceptSurface(_ side: Speaker) {
        state.acceptSurface(side)
    }

    /// Choose another conversation for a connected side: the connection is
    /// dropped and the picker opens for that side alone.
    func chooseAnother(_ side: Speaker) {
        engine.unbind(side)
        state.disconnect(side)
        beginPicking(side)
    }

    // MARK: Keys

    /// The picker's keys, from the panel: arrows move among the windows,
    /// Return connects the one stood on, Escape cancels. Outside the
    /// picker, Return on a connect screen starts picking. Returns whether
    /// the key was taken.
    func handleKey(_ event: NSEvent) -> Bool {
        let key = event.keyCode
        if draggingSide != nil {
            if key == 53 { cancelDragging() }
            return true
        }
        guard picker != nil else {
            if case .connect(let side) = state.phase, key == 36 || key == 76 {
                beginPicking(side)
                return true
            }
            return false
        }
        switch key {
        case 126: movePick(by: -1)      // up
        case 125: movePick(by: 1)       // down
        case 36, 76: choosePick()       // Return, keypad Enter
        case 53: cancelPicking()        // Escape
        default: return false
        }
        return true
    }

    /// Escape from the panel's cancel path: true when the picker took it.
    func cancelIfPicking() -> Bool {
        if draggingSide != nil {
            cancelDragging()
            return true
        }
        guard picker != nil else { return false }
        cancelPicking()
        return true
    }

    // MARK: Runs, returns, restarts

    func runStarted() {
        cancelPicking()
        problem = nil
        state.runStarted()
    }

    /// Another topic in these conversations: both are verified again
    /// before Send is offered.
    func revalidate() {
        problem = nil
        state.markUnverified()
        engine.requestSweep()
    }

    /// Set up fresh conversations: both sides connect anew.
    func setUpFresh() {
        cancelPicking()
        problem = nil
        engine.unbind(.chatgpt)
        engine.unbind(.claude)
        state.reconnectBoth()
        engine.requestSweep()
    }

    /// Guided setup from the top.
    func restart() {
        cancelPicking()
        problem = nil
        engine.unbind(.chatgpt)
        engine.unbind(.claude)
        arrangedTargets = nil
        state.restart()
        engine.requestSweep()
    }

    // MARK: The highlight

    private func updateHighlight() {
        guard let picker, let candidate = picker.current, let frame = candidate.frame,
              !candidate.isMinimized else {
            highlight.hide()
            return
        }
        highlight.show(frame: frame, label: "\(name(picker.side)) \u{00B7} \(candidate.name)")
    }

    private func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

// The app's model: form state, the log, and the start/stop wiring around
// the relay engine. UI-facing state is @Published and mutated on the main
// thread only; runs and inspections live on worker threads so the panel's
// event loop stays free.

import AppKit
import ApplicationServices
import Combine
import Foundation

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

final class RelayController: ObservableObject {
    /// The picker tag for free-form instructions; not a ConversationTemplate.
    static let customConversation = "Custom"
    /// The selected template's name, or customConversation.
    @Published var conversation = conversationTemplates[0].name
    /// Completes the selected template ("What to brainstorm about").
    @Published var topic = ""
    /// The full opening text while the editor is open. The picker continues
    /// to name the selected template; Custom is reserved for a prompt written
    /// from scratch.
    @Published var customInstructions = ""
    /// Editing is presentation state, not a conversation choice. Keeping it
    /// separate prevents Edit from silently changing the picker to Custom.
    @Published private(set) var isEditingInstructions = false
    @Published var limitTurns = config.limitTurns
    @Published var turns = config.turns
    /// Which side sends the opening message. Chosen before a run — the
    /// wireframe skin's courier points at whoever is nominated — and copied
    /// into config at Start, which is where the relay loop reads it.
    @Published var firstSpeaker = Speaker.chatgpt
    @Published var tileWindows = false
    @Published var isRunning = false
    /// Whether a pause has been *asked for* (see relayPaused). The run keeps
    /// going until it reaches the next handoff.
    @Published var isPaused = false
    /// Whether the run has actually parked at that handoff. Between the two
    /// the agent that was composing is still finishing its reply, which is
    /// the gap the panel's route draws.
    @Published var isHolding = false
    /// Whether the steering editor is open. Steer asks for a pause the way
    /// the Pause control does — room to write — and posting or canceling
    /// the note releases that pause only if Steer was what asked for it.
    @Published var isSteering = false
    /// The note being written in the steering editor.
    @Published var steeringText = ""
    /// Whether the current pause exists on Steer's account rather than a
    /// Pause press of the user's own; cleared whenever the user toggles
    /// the pause by hand, which takes ownership of it.
    private var steerInitiatedPause = false
    /// Panel presentation state, glass skin only: a run shrinks the panel to
    /// the companion pane; the user can expand back mid-run. The AppKit shell
    /// watches this (with logOpen) to animate the glass panel's frame; the
    /// classic skin ignores it.
    @Published var compact = false
    /// Whether the glass skin's log drawer is open.
    @Published var logOpen = false
    @Published var logLines: [LogLine] = []
    @Published var chatgptStatus = SideStatus(appName: "ChatGPT")
    @Published var claudeStatus = SideStatus(appName: "Claude")
    @Published var chatgptConversation = ConversationStatus.notStarted
    @Published var claudeConversation = ConversationStatus.notStarted
    /// The running turn number (1-based) during a relay run; 0 outside one.
    /// Feeds the wireframe skin's odometer.
    @Published var currentTurn = 0
    private var nextLogID = 0
    /// Preserve in-progress full-prompt edits while someone compares shapes.
    /// A deliberate reset removes the draft for that shape.
    private var instructionDrafts: [String: String] = [:]
    private let scanner = ReadinessScanner()
    private var panelVisible = false
    /// Set by the AppKit shell; the skins' gear button routes here to open
    /// the settings window above the panel.
    var openSettingsHandler: (() -> Void)?
    private var templatesWatcher: AnyCancellable?

    init() {
        // Most sweeps see the same picture as the last one; publishing them
        // anyway would re-render every observing skin each poll, so only
        // changed statuses reach the @Published properties.
        scanner.onUpdate = { [weak self] chatgpt, claude in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.chatgptStatus != chatgpt { self.chatgptStatus = chatgpt }
                if self.claudeStatus != claude { self.claudeStatus = claude }
            }
        }
        conversationStatusSink = { [weak self] chatgpt, claude in
            DispatchQueue.main.async {
                self?.chatgptConversation = chatgpt
                self?.claudeConversation = claude
            }
        }
        relayTurnSink = { [weak self] turn in
            DispatchQueue.main.async { self?.currentTurn = turn }
        }
        relayHoldingSink = { [weak self] holding in
            DispatchQueue.main.async { self?.isHolding = holding }
        }
        // A shape deleted or renamed in Settings can leave the picker
        // pointing at nothing; follow the list to its first shape (which
        // always exists — the store refuses to empty the list).
        templatesWatcher = SettingsStore.shared.$templates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] templates in
                guard let self, conversation != Self.customConversation,
                      !templates.contains(where: { $0.name == self.conversation })
                else { return }
                selectConversation(templates.first?.name ?? Self.customConversation)
            }
    }

    func openSettings() {
        openSettingsHandler?()
    }

    /// nil means the picker is on Custom.
    var selectedTemplate: ConversationTemplate? {
        conversationTemplates.first { $0.name == conversation }
    }

    /// Custom always needs the full editor. A template starts with its compact
    /// topic field and stays in the full editor once the user asks to edit it.
    var showsFullInstructionsEditor: Bool {
        selectedTemplate == nil || isEditingInstructions
    }

    /// A visual hint at the insertion point in the full editor. It is never
    /// part of customInstructions, so an untouched placeholder cannot leak
    /// into the message sent to either agent.
    var promptEditorPlaceholder: String? {
        if let template = selectedTemplate {
            let topicIsEmpty = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let editorStillHasOnlyTheTemplate =
                customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
                == template.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return topicIsEmpty && editorStillHasOnlyTheTemplate
                ? "(add your topic or material here)" : nil
        }
        return customInstructions.isEmpty ? "Write your complete opening prompt here…" : nil
    }

    /// The exact initial message the relay will hand to the first agent
    /// (before the framing preamble): the template composed with the topic,
    /// or the full editor's text as written.
    var composedInstructions: String {
        guard !showsFullInstructionsEditor,
              let template = selectedTemplate else { return customInstructions }
        return template.composed(topic: topic)
    }

    /// Whether Start has something to send: a topic in compact template mode,
    /// or any text when the full prompt is being edited.
    var instructionsReady: Bool {
        guard showsFullInstructionsEditor else {
            return !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let text = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        // Opening a template before entering a topic should not make Run look
        // ready merely because the template body itself is non-empty. Any
        // actual edit makes the full prompt independently valid.
        if let template = selectedTemplate,
           topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text == template.body.trimmingCharacters(in: .whitespacesAndNewlines) {
            return false
        }
        return true
    }

    /// Select a shape without changing whether the user is working in the
    /// compact topic field or the full editor. Full-prompt drafts are kept per
    /// shape so comparing options does not silently throw work away.
    func selectConversation(_ name: String) {
        guard name == Self.customConversation
                || conversationTemplates.contains(where: { $0.name == name }),
              name != conversation else { return }

        if showsFullInstructionsEditor {
            instructionDrafts[conversation] = customInstructions
        }

        let keepEditorOpen = showsFullInstructionsEditor
        conversation = name

        if name == Self.customConversation {
            customInstructions = instructionDrafts[name] ?? ""
            isEditingInstructions = true
        } else if keepEditorOpen {
            let template = conversationTemplates.first { $0.name == name }!
            customInstructions = instructionDrafts[name]
                ?? template.composed(topic: topic)
            isEditingInstructions = true
        } else {
            isEditingInstructions = false
        }
    }

    /// Reveal the selected template's composed message for direct editing
    /// without relabeling the selection as Custom.
    func editInstructions() {
        guard selectedTemplate != nil, !isEditingInstructions else { return }
        customInstructions = composedInstructions
        isEditingInstructions = true
    }

    /// Explicitly discard this shape's full-prompt edits and return to the
    /// template's topic field. This is the only action that collapses it.
    func resetInstructionsToTemplate() {
        guard selectedTemplate != nil else { return }
        instructionDrafts.removeValue(forKey: conversation)
        customInstructions = ""
        isEditingInstructions = false
    }

    /// The readiness strip only scans while someone can see it, and never
    /// while a run owns the apps' AX trees and the machine's focus.
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        updateScanner()
    }

    private func updateScanner() {
        scanner.setActive(panelVisible && !isRunning)
    }

    /// Main thread only (the logSink wrapper in MenuBarController dispatches).
    func append(_ line: String) {
        logLines.append(LogLine(id: nextLogID, text: line))
        nextLogID += 1
    }

    func start() {
        guard !isRunning else { return }

        guard instructionsReady else {
            append(showsFullInstructionsEditor
                ? "Write the instructions first — they become the opening message handed to the first agent."
                : "Add a topic first — it completes the \(conversation) opening handed to the first agent.")
            return
        }
        guard ensureTrusted(), let apps = resolveApps() else { return }

        config.seed = composedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.first = firstSpeaker
        let tile = tileWindows

        isRunning = true
        isPaused = false
        isHolding = false
        isSteering = false
        steeringText = ""
        steerInitiatedPause = false
        relayPaused.set(false)
        relaySteering.clear()
        compact = true
        updateScanner()
        relayCancelled.set(false)
        chatgptConversation = .notStarted
        claudeConversation = .notStarted
        currentTurn = 0
        let origin = currentFrontmostApp()
        log("Run starting. Transcript: \(config.transcriptPath)")

        runOnWorkerThread { [weak self] in
            enableElectronAccessibility(apps.chatgpt)
            enableElectronAccessibility(apps.claude)
            usleep(700_000) // let the trees populate
            if tile { arrangeSideBySide(left: apps.chatgpt, right: apps.claude) }
            _ = runRelay(chatgpt: apps.chatgpt, claude: apps.claude)
            refocus(to: origin)
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isPaused = false
                self?.isHolding = false
                self?.isSteering = false
                self?.steeringText = ""
                self?.steerInitiatedPause = false
                relayPaused.set(false)
                self?.compact = false
                self?.updateScanner()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        // Clear any pause so the loop wakes and reaches its cancel check;
        // a half-written steering note has nothing left to steer.
        isPaused = false
        isSteering = false
        steeringText = ""
        steerInitiatedPause = false
        relayPaused.set(false)
        relayCancelled.set(true)
        append("Stop requested — ending the run at the next safe point...")
    }

    /// Pause holds the run at the next handoff boundary; the agent currently
    /// composing finishes its reply, which is captured but not delivered
    /// until Resume.
    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        relayPaused.set(isPaused)
        // A pause toggled by hand is the user's own, whichever way it went.
        steerInitiatedPause = false
        if isPaused {
            append("Pause requested — the run holds at the next handoff.")
        }
    }

    /// Steer: hold the run and write a note into the conversation. The note
    /// rides the next handoff to whoever replies next, and is echoed to the
    /// other side a turn later, so both learn of it and in what order.
    func beginSteer() {
        guard isRunning, !isSteering else { return }
        isSteering = true
        steeringText = ""
        if isPaused {
            append("Steer — the run is already pausing; the note rides the handoff when you resume.")
        } else {
            steerInitiatedPause = true
            isPaused = true
            relayPaused.set(true)
            append("Steer — the run holds at the next handoff while you write.")
        }
    }

    func sendSteering() {
        let note = steeringText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRunning, isSteering, !note.isEmpty else { return }
        relaySteering.post(note)
        closeSteer()
        append(isPaused
            ? "Steering note posted — it rides the handoff when you resume."
            : "Steering note posted — it rides the next handoff.")
    }

    func cancelSteer() {
        guard isSteering else { return }
        closeSteer()
        append(isPaused ? "Steer called off — the run stays paused." : "Steer called off.")
    }

    /// Close the editor, and release the pause if Steer asked for it; a
    /// pause the user requested themselves outlives the editor.
    private func closeSteer() {
        isSteering = false
        steeringText = ""
        if steerInitiatedPause {
            steerInitiatedPause = false
            isPaused = false
            relayPaused.set(false)
        }
    }

    /// Dump both apps' windows, buttons, and selector matches into the log —
    /// the way selector breakage gets diagnosed after an app update.
    func runInspect() {
        guard !isRunning else { return }
        guard ensureTrusted(), let apps = resolveApps() else { return }
        append("Inspecting both apps...")
        runOnWorkerThread { [weak self] in
            enableElectronAccessibility(apps.chatgpt)
            enableElectronAccessibility(apps.claude)
            usleep(700_000)
            let report = inspectReport(apps.chatgpt) + "\n\n" + inspectReport(apps.claude)
            DispatchQueue.main.async { self?.append(report) }
        }
    }

    /// Put the chat windows back where they were before the last tiling.
    func restoreWindows() {
        guard !isRunning else { return }
        guard ensureTrusted(), let apps = resolveApps() else { return }
        runOnWorkerThread {
            unarrange([apps.chatgpt, apps.claude])
        }
    }

    func openTranscript() {
        let url = URL(fileURLWithPath: config.transcriptPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            append("No transcript yet at \(config.transcriptPath).")
        }
    }

    /// Prompting on demand (not at app launch) means the permission dialog
    /// appears while the user is looking at the panel, not out of nowhere.
    private func ensureTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) { return true }
        append("Accessibility permission missing. Grant Errol in System Settings > Privacy & Security > Accessibility, then try again.")
        return false
    }

    private func resolveApps() -> (chatgpt: TargetApp, claude: TargetApp)? {
        guard let chatgpt = findApp(bundleID: config.chatgptBundleID, name: "Codex",
                                    selectors: config.chatgptSelectors) else {
            append("ERROR: Codex/ChatGPT (\(config.chatgptBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        guard let claude = findApp(bundleID: config.claudeBundleID, name: "Claude",
                                   selectors: config.claudeSelectors) else {
            append("ERROR: Claude Desktop (\(config.claudeBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        return (chatgpt, claude)
    }

    /// The deep AX tree walks need more stack than the default worker thread
    /// provides.
    private func runOnWorkerThread(_ work: @escaping () -> Void) {
        let worker = Thread(block: work)
        worker.stackSize = 4 << 20
        worker.start()
    }
}

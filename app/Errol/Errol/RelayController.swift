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
    /// The full opening text when the picker is on Custom — either written
    /// from scratch or handed over by editInstructions().
    @Published var customInstructions = ""
    @Published var limitTurns = config.limitTurns
    @Published var turns = config.turns
    /// Which side sends the opening message. Chosen before a run — the
    /// wireframe skin's courier points at whoever is nominated — and copied
    /// into config at Start, which is where the relay loop reads it.
    @Published var firstSpeaker = Speaker.chatgpt
    @Published var newChats = false
    @Published var tileWindows = false
    @Published var isRunning = false
    /// Whether a pause has been *asked for* (see relayPaused). The run keeps
    /// going until it reaches the next handoff.
    @Published var isPaused = false
    /// Whether the run has actually parked at that handoff. Between the two
    /// the agent that was composing is still finishing its reply, which is
    /// the gap the panel's route draws.
    @Published var isHolding = false
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
    private let scanner = ReadinessScanner()
    private var panelVisible = false

    init() {
        scanner.onUpdate = { [weak self] chatgpt, claude in
            DispatchQueue.main.async {
                self?.chatgptStatus = chatgpt
                self?.claudeStatus = claude
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
    }

    /// nil means the picker is on Custom.
    var selectedTemplate: ConversationTemplate? {
        conversationTemplates.first { $0.name == conversation }
    }

    /// The exact initial message the relay will hand to the first agent
    /// (before the framing preamble): the template composed with the topic,
    /// or the custom text as written.
    var composedInstructions: String {
        guard let template = selectedTemplate else { return customInstructions }
        return template.composed(topic: topic)
    }

    /// Whether Start has something to send: a topic in template mode, any
    /// text in Custom mode.
    var instructionsReady: Bool {
        let text = selectedTemplate == nil ? customInstructions : topic
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The "Edit instructions" link: reveal the composed message as editable
    /// custom text. One-way by design — re-picking a template recomposes from
    /// the template and the last topic, discarding the edits.
    func editInstructions() {
        customInstructions = composedInstructions
        conversation = Self.customConversation
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
            append(selectedTemplate == nil
                ? "Write the instructions first — they become the opening message handed to the first agent."
                : "Add a topic first — it completes the \(conversation) opening handed to the first agent.")
            return
        }
        guard ensureTrusted(), let apps = resolveApps() else { return }

        config.seed = composedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.newChats = newChats
        config.first = firstSpeaker
        let tile = tileWindows

        isRunning = true
        isPaused = false
        isHolding = false
        relayPaused.set(false)
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
                relayPaused.set(false)
                self?.compact = false
                self?.updateScanner()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        // Clear any pause so the loop wakes and reaches its cancel check.
        isPaused = false
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
        if isPaused {
            append("Pause requested — the run holds at the next handoff.")
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

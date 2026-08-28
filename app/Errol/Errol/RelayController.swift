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
    @Published var seed = ""
    @Published var limitTurns = config.limitTurns
    @Published var turns = config.turns
    @Published var newChats = false
    @Published var tileWindows = false
    @Published var isRunning = false
    @Published var logLines: [LogLine] = []
    @Published var chatgptStatus = SideStatus(appName: "ChatGPT")
    @Published var claudeStatus = SideStatus(appName: "Claude")
    @Published var chatgptConversation = ConversationStatus.notStarted
    @Published var claudeConversation = ConversationStatus.notStarted
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

        let instruction = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            append("Type an instruction first — it becomes the opening message handed to the first agent.")
            return
        }
        guard ensureTrusted(), let apps = resolveApps() else { return }

        config.seed = instruction
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.newChats = newChats
        let tile = tileWindows

        isRunning = true
        updateScanner()
        relayCancelled.set(false)
        chatgptConversation = .notStarted
        claudeConversation = .notStarted
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
                self?.updateScanner()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        relayCancelled.set(true)
        append("Stop requested — ending the run at the next safe point...")
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

import AppKit
import ApplicationServices
@testable import ErrolKit

/// Owns the exact selected window. A conversation URL (when exposed) is also
/// pinned for existing chats. A new chat may acquire its first conversation URL.
final class TargetBinding {
    let target: TargetApp
    let window: AXUIElement
    private var conversationURL: String?
    private let newConversation: Bool
    private let initialIdentity: String?
    private var submitted = false
    var hasConversationIdentity: Bool { conversationURL != nil }
    init?(_ target: TargetApp, context: ConversationSetup) {
        guard let window = chatWindow(in: target) else { return nil }
        self.target = target
        self.window = window
        newConversation = context == .new
        initialIdentity = Self.identity(window)
        if context != .new { conversationURL = Self.identity(window) }
    }
    func valid() -> Bool {
        guard !target.app.isTerminated, let current = chatWindow(in: target), CFEqual(current, window) else { return false }
        let identity = Self.identity(current)
        if let conversationURL, identity != conversationURL { return false }
        if newConversation, submitted, conversationURL == nil, let identity, identity != initialIdentity { conversationURL = identity }
        return true
    }
    func didSubmit() { submitted = true }
    static func identity(_ window: AXUIElement) -> String? {
        var areas: [AXUIElement] = []
        findAll(in: window, where: { axAttribute($0, kAXRoleAttribute) as? String == "AXWebArea" }, into: &areas)
        if let url = areas.compactMap({ (axAttribute($0, "AXURL") as? URL) }).last(where: {
            ["claude.ai", "chatgpt.com", "chat.openai.com"].contains($0.host ?? "") && $0.path != "/new" && !$0.path.isEmpty && $0.path != "/"
        }) { return url.absoluteString }
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? ""
        return ["", "Claude", "ChatGPT", "Codex", "New chat", "New task"].contains(title) ? nil : "title:" + title
    }
}

/// A separate overall deadline: a permanently visible Stop control must not
/// keep a compatibility test alive forever. The parent report is checkpointed
/// before entry, so even the hard deadline cannot leave a green result.
final class CaseDeadline {
    private let lock = NSLock()
    private var expired = false
    private var interrupted = false
    private var timers: [DispatchSourceTimer] = []
    private var signals: [DispatchSourceSignal] = []
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return expired }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return interrupted }
    init(seconds: Double, emergency: URL) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.expired = true; self.lock.unlock()
            relayControl.cancel()
        }
        timer.resume(); timers.append(timer)
        let hard = DispatchSource.makeTimerSource(queue: .global())
        hard.schedule(deadline: .now() + seconds + 20)
        hard.setEventHandler {
            try? "Hard deadline reached: an app or AX call did not return. The active case is incomplete. Inspect leftover test draft/attachments before resuming.\n"
                .write(to: emergency, atomically: true, encoding: .utf8)
            _exit(124)
        }
        hard.resume(); timers.append(hard)
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock(); self.interrupted = true; self.lock.unlock()
                relayControl.cancel()
            }
            source.resume(); signals.append(source)
        }
    }
    func stop() {
        timers.forEach { $0.cancel() }; timers.removeAll()
        signals.forEach { $0.cancel() }; signals.removeAll()
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL)
    }
    deinit { stop() }
}

private final class HoldProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var passed = false
    private var observed = false
    func observeAndResume(clipboard: Int, focus: pid_t?, note: String) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        passed = NSPasteboard.general.changeCount == clipboard && axFocusedPID() == focus &&
            relayControl.canOpenSteering && !relayControl.hasFocusOperation
        observed = true
        relayControl.finishSteering(note: note)
    }
    func finish() -> (observed: Bool, passed: Bool) {
        lock.lock(); defer { lock.unlock() }
        active = false
        return (observed, passed)
    }
}

func resolve(_ endpoint: Endpoint) -> TargetApp? {
    let app = endpoint.app
    return findApp(bundleID: app == .chatgpt ? config.chatgptBundleID : config.claudeBundleID,
                   name: app == .chatgpt ? "ChatGPT" : "Claude",
                   selectors: app == .chatgpt ? config.chatgptSelectors : config.claudeSelectors)
}

func attachmentControls(_ input: AXUIElement, target: TargetApp) -> [AXUIElement] {
    var container = input
    for _ in 0..<max(1, target.selectors.pastedTextAttachmentAncestorLevels) {
        guard let parent = axAttribute(container, kAXParentAttribute),
              axAttribute(parent as! AXUIElement, kAXRoleAttribute) as? String == "AXGroup" else { break }
        container = parent as! AXUIElement
    }
    var controls: [AXUIElement] = []
    findAll(in: container, where: { element in
        guard axAttribute(element, kAXRoleAttribute) as? String == "AXButton" else { return false }
        let label = axLabel(element).lowercased()
        return label.hasPrefix("remove ") || label.hasPrefix("delete attachment")
    }, into: &controls)
    return controls
}

/// Kept pure so safety preconditions and unobservable states can be tested
/// without fake keyboard events or accessibility permission.
func composerSafety(value: String?, attachments: Int, busy: Bool) -> VerificationCheck {
    if busy { return .init(name: "idle-composer", status: .blocked, detail: "Conversation is busy; nothing will be sent") }
    guard let value else { return .init(name: "readable-composer", status: .inconclusive, detail: "Composer AXValue is unreadable; cannot exclude an existing draft") }
    if attachments > 0 { return .init(name: "empty-composer", status: .blocked, detail: "Existing attachment; nothing will be sent") }
    if !composerPlaceholders.contains(value) { return .init(name: "empty-composer", status: .blocked, detail: "Existing draft (including whitespace); nothing will be sent") }
    return .init(name: "empty-composer", status: .passed, detail: "Readable empty composer, no observed attachments, idle")
}

func pasteChecks(expected: String, value: String?, before: Int, after: Int, receipt: PasteReceipt?) -> [VerificationCheck] {
    if after - before > 1 {
        return [.init(name: "paste-once", status: .failed, detail: "More than one attachment appeared for one paste")]
    }
    if let value, Data(value.utf8) == Data(expected.utf8) {
        return [.init(name: "paste-integrity", status: .passed, detail: "Exact UTF-8 match (\(expected.utf8.count) bytes, SHA-256 \(sha256(expected)))")]
    }
    if receipt == .attachment, after == before + 1 {
        return [.init(name: "paste-once", status: .passed, detail: "Exactly one pasted-text attachment appeared"),
                .init(name: "paste-integrity", status: .inconclusive, detail: "Attachment content is not exposed as composer text; byte fidelity unverified")]
    }
    return [.init(name: "paste-integrity", status: .failed, detail: "Composer does not exactly match expected payload; submission stopped")]
}

final class LiveScenarioRunner {
    let options: VerificationOptions
    let evidence: CaseEvidence
    let nonce: String
    private let returnFocus: NSRunningApplication?
    private var bindings: [String: TargetBinding] = [:]
    private var deadlines: CaseDeadline?
    private var cleanup: [(AXUIElement, String, [AXUIElement], TargetBinding)] = []
    private var pasteCount = 0
    private var submitCount = 0
    private var stopAfterCase = false
    var shouldStop: Bool { stopAfterCase }

    init(options: VerificationOptions, evidence: CaseEvidence, nonce: String, returnFocus: NSRunningApplication? = nil) {
        self.options = options; self.evidence = evidence; self.nonce = nonce
        self.returnFocus = returnFocus
    }

    func run() -> CaseResult {
        let desktopLease: DesktopLease
        do { desktopLease = try DesktopLease() }
        catch { evidence.check("desktop-ownership", .blocked, String(describing: error)); return evidence.finish() }
        defer { desktopLease.release() }
        let savedConfig = config
        let clipboard = ClipboardLease()
        let originalFocus = returnFocus ?? currentFrontmostApp()
        config.maxChars = options.cap
        config.timeout = min(120, options.timeout)
        relayControl.reset()
        let deadline = CaseDeadline(seconds: options.timeout, emergency: evidence.directory.appendingPathComponent("deadline.txt"))
        deadlines = deadline
        perform()
        if deadline.timedOut { evidence.check("case-deadline", .failed, "Exceeded overall \(options.timeout)s deadline") }
        if deadline.cancelled { evidence.check("interrupted", .blocked, "Operator interrupted the case"); stopAfterCase = true }
        cleanUp()
        evidence.check("clipboard-restored", clipboard.restore() ? .passed : .failed, "Restored all captured pasteboard items and data types")
        if !deadline.cancelled { refocus(to: originalFocus) }
        deadline.stop()
        deadlines = nil
        config = savedConfig
        return evidence.finish()
    }

    private func perform() {
        let scenario = evidence.result.scenario
        guard let target = prepare(scenario.endpoint, context: scenario.conversation) else { return }
        if let peer = scenario.peer {
            guard let other = prepare(peer, context: .existing) else { return }
            runPair(target, other)
            return
        }
        guard let input = inputArea(in: target) else { evidence.check("composer", .failed, "No composer"); return }
        let value = axAttribute(input, kAXValueAttribute) as? String
        let attachments = attachmentControls(input, target: target)
        let busy = hasStopButton(in: target)
        let safety = composerSafety(value: value, attachments: attachments.count, busy: busy)
        if [.draftGuard, .attachmentGuard, .busyGuard].contains(scenario.behavior) {
            let prepared: Bool
            switch scenario.behavior {
            case .draftGuard: prepared = value == "ERROL-DRAFT-GUARD" && !busy && attachments.isEmpty
            case .attachmentGuard: prepared = !attachments.isEmpty && !busy
            default: prepared = busy
            }
            guard prepared else { evidence.check("guard-setup", .blocked, "Requested draft/attachment/busy precondition is absent"); return }
            evidence.check("harness-refuses-send", safety.status == .blocked ? .passed : .failed, "Harness preflight: \(safety.detail). Production send was not called.")
            usleep(250_000)
            let same = (axAttribute(input, kAXValueAttribute) as? String) == value && attachmentControls(input, target: target).count == attachments.count
            evidence.check("draft-preserved", same ? .passed : .failed, "Compared composer and attachments without writing to either")
            return
        }
        evidence.check(safety.name, safety.status, safety.detail)
        guard safety.status == .passed else { return }
        let before = evidence.capture(target, stage: "before", screenshots: options.screenshots)
        let baseline = responseBaseline(in: target)
        let contextOK = scenario.conversation == .new ? baseline.affordances == 0 && (before?.root.messages.isEmpty == true) : baseline.affordances > 0
        guard contextOK else { evidence.check("conversation-state", .blocked, "Displayed conversation does not match \(scenario.conversation.rawValue) setup"); return }
        evidence.check("conversation-state", .passed, "\(scenario.conversation.rawValue); baseline \(baseline.affordances), ordinal \(baseline.lastOrdinal.map(String.init) ?? "unavailable")")
        if scenario.conversation == .long {
            guard let ordinal = baseline.lastOrdinal, ordinal >= 12 else {
                evidence.check("long-history", .inconclusive, "Cannot independently verify at least 12 historical messages on this surface"); return
            }
            evidence.check("long-history", .passed, "Newest ordinal \(ordinal); \(before?.root.messages.count ?? 0) message containers mounted")
        }
        guard checkFocusSetup(target, scenario: scenario) else { return }
        let payload = scenario.payload.text(nonce: nonce, cap: options.cap)
        let expected = truncatedForRelay(payload)
        evidence.text(payload, name: "input.txt")
        evidence.text(expected, name: "expected-paste.txt")
        evidence.event("payload", ["characters": payload.count, "bytes": payload.utf8.count, "expectedHash": sha256(expected), "truncated": payload != expected])
        let prompt: String
        if scenario.behavior == .streaming {
            prompt = "Automated UI test; no tools or commands. Write the numbers 1 through 400, each on its own line. End with the word ACK, one space, and this identifier: \(nonce)."
            evidence.text(prompt, name: "input.txt"); evidence.text(prompt, name: "expected-paste.txt")
        } else { prompt = payload }
        let outcome = send(prompt, to: target, inspection: inspection(target))
        if scenario.behavior == .focusLoss {
            evidence.check("no-submission-after-focus-loss", outcome == .abandoned && submitCount == 0 ? .passed : .failed,
                           "Production send: \(outcome); \(submitCount) submission attempts after the focus-loss checkpoint")
            let after = responseBaseline(in: target)
            evidence.check("message-count-unchanged", after.affordances == baseline.affordances && after.lastOrdinal == baseline.lastOrdinal ? .passed : .failed,
                           "Response counters must not advance in a paste-only refusal case")
            return
        }
        evidence.check("submission", outcome == .confirmed ? .passed : .failed, "Production send outcome: \(outcome); \(pasteCount) paste(s), \(submitCount) submission attempt(s)")
        guard outcome == .confirmed else { return }
        bindings[target.name]?.didSubmit()
        let absorbed = absorbEchoIntoBaseline(in: target, preSend: baseline)
        guard wait(target, baseline: absorbed, requireStreaming: scenario.behavior == .streaming) else { return }
        guard bindings[target.name]?.valid() == true else { evidence.check("target-retained", .failed, "Window/conversation changed before copy"); return }
        if bindings[target.name]?.hasConversationIdentity != true {
            evidence.check("conversation-identity", .inconclusive, "No distinct conversation identity was exposed after submission")
        }
        let responseSnapshot = evidence.capture(target, stage: "response", screenshots: options.screenshots)
        if scenario.behavior == .collapsedCopy {
            let collapsed = messageAffordances(in: target).last.map { isMessageActionsToggle($0, selectors: target.selectors) } == true
            evidence.check("collapsed-copy-setup", collapsed ? .passed : .inconclusive, "Newest response action bar \(collapsed ? "is collapsed" : "is not collapsed; expansion path untested")")
        }
        guard let reply = copyLastResponse(from: target) else { evidence.check("copy", .failed, "Production copy returned no response"); return }
        evidence.text(reply, name: "copied-response.txt")
        evidence.text(NSPasteboard.general.string(forType: .string) ?? "", name: "raw-clipboard-response.txt")
        let expectedReply = "ACK \(nonce)"
        let correct = scenario.behavior == .streaming ? reply.hasSuffix(expectedReply) : reply == expectedReply
        evidence.check("reply-contract", correct ? .passed : .inconclusive,
                       correct ? "Fresh case identifier and expected reply shape matched" : "Unexpected response: inspect model compliance, app errors, and copy identity separately")
        verifyTranscript(responseSnapshot, payload: truncatedForRelay(prompt), expectedReply: reply, nonce: nonce)
        if submitCount != 1 { evidence.check("submission-retries", .inconclusive, "Production needed \(submitCount) submission attempts; inspect sent-message evidence for duplicates") }
    }

    private func prepare(_ endpoint: Endpoint, context: ConversationSetup) -> TargetApp? {
        guard let target = resolve(endpoint) else { evidence.check("running-\(endpoint.id)", .blocked, "Application is not running"); return nil }
        AXUIElementSetMessagingTimeout(target.ax, 2)
        enableElectronAccessibility(target)
        usleep(700_000)
        guard let binding = TargetBinding(target, context: context) else { evidence.check("window", .failed, "No targetable window"); return nil }
        let side = composeSideStatus(appName: target.name, scans: [scanWindow(LiveElement(ax: binding.window), selectors: target.selectors)], selectors: target.selectors)
        evidence.event("target", ["app": endpoint.app.rawValue, "surface": side.surface ?? "unknown", "model": side.model ?? "unknown",
                                  "pid": target.app.processIdentifier, "focus": focusReport(target)])
        guard side.state == .ready, side.surface?.caseInsensitiveCompare(endpoint.surface) == .orderedSame else {
            evidence.capture(target, stage: "wrong-surface", screenshots: options.screenshots)
            evidence.check("surface", .blocked, "Expected \(endpoint.surface); observed \(side.surface ?? "unknown") / \(side.headline)")
            return nil
        }
        evidence.check("surface-\(endpoint.id)", .passed, "Detected \(side.surface ?? "?") in selected window")
        bindings[target.name] = binding
        if context != .new, TargetBinding.identity(binding.window) == nil {
            evidence.check("conversation-identity", .inconclusive, "Window is pinned, but this UI exposes no distinct conversation URL/title")
        }
        return target
    }

    private func checkFocusSetup(_ target: TargetApp, scenario: DesktopScenario) -> Bool {
        let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute)
        switch scenario.behavior {
        case .background:
            guard !isFrontmost(target) else { evidence.check("background-setup", .blocked, "Target is still frontmost"); return false }
        case .wrongField:
            guard isFrontmost(target), let focused, axAttribute(focused as! AXUIElement, kAXRoleAttribute) as? String == "AXTextField" else {
                evidence.check("wrong-field-setup", .blocked, "Focus a search field in the target app"); return false
            }
        case .multipleWindows:
            guard axWindows(target).count >= 2 else { evidence.check("multiwindow-setup", .blocked, "Fewer than two windows available on this build"); return false }
            guard let focusedWindow = axAttribute(target.ax, kAXFocusedWindowAttribute), let binding = bindings[target.name], CFEqual(focusedWindow, binding.window) else {
                evidence.check("target-window", .failed, "Production window choice differs from the focused test window"); return false
            }
        default: break
        }
        return true
    }

    private func inspection(_ target: TargetApp) -> SendInspection {
        SendInspection(event: { [self] event in
            if event.hasPrefix("paste-attempt") { pasteCount += 1 }
            if event.hasPrefix("submit-attempt") { submitCount += 1 }
            evidence.event(event, ["app": target.name])
        }, mayContinue: { [self] in
            !relayControl.isCancelled && evidence.writeError == nil && bindings[target.name]?.valid() == true
        }, inspectPaste: { [self] input, payload, before, after, receipt in
            let value = input.flatMap { axAttribute($0, kAXValueAttribute) as? String }
            let checks = pasteChecks(expected: payload, value: value, before: before, after: after, receipt: receipt)
            checks.forEach { evidence.check($0.name, $0.status, $0.detail) }
            if let value { evidence.text(value, name: "composer-\(pasteCount).txt") }
            if let input, let binding = bindings[target.name] {
                cleanup.append((input, payload, attachmentControls(input, target: target), binding))
            }
            evidence.capture(target, stage: "pasted-\(target.name.lowercased())", screenshots: options.screenshots)
            if evidence.result.scenario.behavior == .focusLoss && !checks.contains(where: { $0.status == .failed }) {
                print("FOCUS CHECK: switch to a DIFFERENT application now. Checking in 5 seconds...")
                fflush(stdout)
                NSSound.beep()
                Thread.sleep(forTimeInterval: 5)
                let lost = !isFrontmost(target)
                evidence.check("focus-loss-observed", lost ? .passed : .blocked, lost ? "Another application owns focus" : "Focus did not move; refusal path untested")
                // When focus did move, let production's own pre-submit guard
                // decide. Otherwise veto this negative test before any send.
                if !lost { return false }
            }
            // No blind recovery paste after a mismatch: preserve the failure.
            return !checks.contains { $0.status == .failed } && evidence.writeError == nil
        })
    }

    private func wait(_ target: TargetApp, baseline: ResponseBaseline, requireStreaming: Bool) -> Bool {
        var sawStreaming = false
        var previousStreaming = false
        var changedTarget = false
        let wait = waitForResponse(in: target, baseline: baseline, mayContinue: { [self] in
            let valid = bindings[target.name]?.valid() == true && evidence.writeError == nil
            if !valid { changedTarget = true }
            return valid
        }, onPoll: { [self] sighting in
            evidence.event("response-poll", ["affordances": sighting.affordances,
                "ordinal": sighting.lastOrdinal as Any? ?? NSNull(), "streaming": sighting.streaming])
            if sighting.streaming && !previousStreaming {
                evidence.capture(target, stage: "streaming", screenshots: options.screenshots)
            }
            sawStreaming = sawStreaming || sighting.streaming
            previousStreaming = sighting.streaming
        })
        var completed = false
        if case .complete = wait { completed = true }
        if changedTarget { evidence.check("target-retained", .failed, "Window/conversation changed or evidence writing failed while waiting") }
        evidence.check("completion", completed ? .passed : .failed,
                       completed ? "Production waitForResponse reached stable completion" : "Production wait ended without completion (\(wait))")
        if requireStreaming {
            evidence.check("streaming-observed", sawStreaming ? .passed : .inconclusive,
                           sawStreaming ? "Busy-to-idle transition observed" : "No sampled busy state; streaming path untested")
        }
        return completed
    }

    private func verifyTranscript(_ snapshot: EvidenceSnapshot?, payload: String, expectedReply: String, nonce: String, relay: Bool = false) {
        guard let snapshot, snapshot.complete else { evidence.check("message-identity", .inconclusive, "No complete response snapshot"); return }
        let messages = snapshot.root.messages
        let users = messages.filter { $0.userMessage && (relay ? $0.text == payload : $0.text.contains(nonce)) }
        if users.count > 1 { evidence.check("one-user-message", .failed, "Found \(users.count) user messages carrying this case identifier") }
        else if let user = users.first {
            evidence.check("one-user-message", .passed, "One independently identified user message carries this case identifier")
            evidence.check("sent-content", Data(user.text.utf8) == Data(payload.utf8) ? .passed : .inconclusive, "Sent message AX text may normalize formatting or hide attachment content; expected SHA-256 \(sha256(payload)), observed \(sha256(user.text))")
        } else { evidence.check("one-user-message", .inconclusive, "UI did not expose a recognizable user message containing the identifier; uniqueness unverified") }
        if let latest = messages.last, latest.assistantMessage {
            evidence.check("copy-identity", latest.text.trimmingCharacters(in: .whitespacesAndNewlines) == expectedReply ? .passed : .failed, "Compared production copy with independently captured newest assistant message")
        } else { evidence.check("copy-identity", .inconclusive, "Newest assistant role/body not independently observable; copy content retained") }
    }

    private func cleanUp() {
        for (_, payload, attachments, binding) in cleanup {
            guard binding.valid() else { evidence.check("cleanup", .inconclusive, "Target changed; did not touch the former composer"); continue }
            guard let input = inputArea(in: binding.target) else { evidence.check("cleanup", .inconclusive, "Composer is unavailable after submission"); continue }
            let current = axAttribute(input, kAXValueAttribute) as? String
            if let current, Data(current.utf8) == Data(payload.utf8) {
                AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "" as CFString)
                usleep(200_000)
            } else if let current, !composerPlaceholders.contains(current) {
                evidence.check("cleanup", .inconclusive, "Unexpected composer content retained for inspection; no destructive keystrokes")
                continue
            }
            // These exact controls were observed on our otherwise empty composer
            // after our paste. Never remove a pre-existing attachment.
            let mounted = attachmentControls(input, target: binding.target)
            for control in attachments where mounted.contains(where: { CFEqual($0, control) }) {
                AXUIElementPerformAction(control, kAXPressAction as CFString)
                usleep(150_000)
            }
            let after = axAttribute(input, kAXValueAttribute) as? String
            let empty = after.map { composerPlaceholders.contains($0) } == true && attachmentControls(input, target: binding.target).isEmpty
            evidence.check("cleanup", empty ? .passed : .inconclusive, empty ? "Composer is empty; no test attachment remains" : "Cannot confirm composer cleanup; inspect it before continuing")
        }
    }

    private func runPair(_ firstTarget: TargetApp, _ secondTarget: TargetApp) {
        let scenario = evidence.result.scenario
        for target in [firstTarget, secondTarget] {
            guard let input = inputArea(in: target) else { evidence.check("composer", .failed, "Missing \(target.name) composer"); return }
            let safe = composerSafety(value: axAttribute(input, kAXValueAttribute) as? String, attachments: attachmentControls(input, target: target).count, busy: hasStopButton(in: target))
            evidence.check("\(target.name)-\(safe.name)", safe.status, safe.detail)
            guard safe.status == .passed else { return }
            evidence.capture(target, stage: "before-\(target.name.lowercased())", screenshots: options.screenshots)
        }
        config.limitTurns = true; config.turns = 6
        config.first = scenario.first == .chatgpt ? .chatgpt : .claude
        config.seed = """
        Automated relay verification. Do not use tools, run commands, edit files, or browse.
        There are six replies TOTAL across both assistants. The first assistant replies with sequence 1.
        Each next reply increments the sequence in the previous assistant's reply by one.
        Every reply is exactly this identifier, one space, and the sequence number: \(nonce)
        On replies 5 and 6 ONLY, append one space followed by [[END-CONVERSATION]].
        Do not include explanation, Markdown, or any other text. Any steering note in this test must preserve this output contract.
        """
        var replies: [(String, String)] = []
        var outcomes: [SendOutcome] = []
        var operation = 0
        let holdProbe = HoldProbe()
        let note = "ERROL-STEERING-\(nonce): Preserve the six-reply output contract."
        let inspection = RelayInspection(sendInspection: { [self] target in self.inspection(target) }, delivered: { [self] target, outcome in
            outcomes.append(outcome)
            if outcome == .confirmed { bindings[target.name]?.didSubmit() }
            evidence.check("delivery-\(outcomes.count)", outcome == .confirmed ? .passed : .failed, "\(target.name): \(outcome)")
            if outcome != .confirmed { relayControl.cancel() }
        }, reply: { [self] target, turn, text in
            replies.append((target.name, text))
            evidence.text(text, name: "reply-\(turn)-\(target.name.lowercased()).txt")
            let snapshot = evidence.capture(target, stage: "reply-\(turn)", screenshots: options.screenshots)
            if let pasted = cleanup.last(where: { $0.3.target.name == target.name }) {
                verifyTranscript(snapshot, payload: pasted.1, expectedReply: text, nonce: nonce, relay: true)
            }
            let expected = "\(nonce) \(turn)" + (turn >= 5 ? " [[END-CONVERSATION]]" : "")
            guard text == expected else { evidence.check("relay-reply-\(turn)", .inconclusive, "Model reply differed from numbered test contract; copy or model behavior requires inspection"); return false }
            evidence.check("relay-reply-\(turn)", .passed, "Expected sequence and current case identifier")
            if scenario.behavior == .cancel && turn == 1 { relayControl.cancel() }
            return true
        }, mayContinue: { [self] target in
            let valid = bindings[target.name]?.valid() == true && evidence.writeError == nil
            if !valid { evidence.check("target-retained", .failed, "Selected conversation changed or evidence writing failed during the relay") }
            return valid
        }, responsePoll: { [self] target, sighting in
            evidence.event("relay-response-poll", ["app": target.name, "affordances": sighting.affordances,
                                                   "ordinal": sighting.lastOrdinal as Any? ?? NSNull(), "streaming": sighting.streaming])
        })
        let report = runRelay(chatgpt: firstTarget, claude: secondTarget, inspection: inspection, operationCompleted: { [self] continuing in
            operation += 1
            if scenario.behavior == .steering && operation == 2 && continuing {
                let grant = relayControl.requestHold()
                evidence.check("hold-during-capture", grant == .afterOperation ? .passed : .failed, "Editor request returns \(grant)")
                let released = relayControl.endOperation(continuingRun: continuing)
                evidence.check("hold-granted", released && relayControl.canOpenSteering ? .passed : .failed, "Capture completion grants editor ownership")
                let beforeHoldClipboard = NSPasteboard.general.changeCount
                let focus = axFocusedPID()
                // Return to the actual relay worker: it now attempts the next
                // delivery and must park at the gate. A separate timer observes
                // the hold and releases it, so this tests real waiting behavior.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    holdProbe.observeAndResume(clipboard: beforeHoldClipboard, focus: focus, note: note)
                }
            } else { _ = relayControl.endOperation(continuingRun: continuing) }
        })
        let hold = holdProbe.finish()
        // The run's own account of its ending, beside the checks made from
        // the outside; a failed start is the one report that ran nothing.
        let succeeded = !report.outcome.isFailedStart
        evidence.event("relay-report", ["outcome": String(describing: report.outcome), "repliesCaptured": report.repliesCaptured,
                                        "signedOffBy": report.signedOffBy.map(\.rawValue) ?? NSNull(), "block": report.block.map { String(describing: $0) } ?? NSNull()])
        if submitCount != outcomes.count {
            evidence.check("relay-submission-retries", .inconclusive, "\(submitCount) submission attempts for \(outcomes.count) handoffs; uniqueness requires inspecting the chats")
        }
        if scenario.behavior == .cancel {
            evidence.check("cancel-stops-handoff", replies.count == 1 && outcomes.count == 1 && relayControl.isCancelled ? .passed : .failed,
                           "\(replies.count) captured replies; \(outcomes.count) sends; cancellation before the second delivery")
        } else {
            evidence.check("relay-six-turns", succeeded && replies.count == 6 && outcomes.count == 6 ? .passed : .inconclusive, "\(replies.count)/6 replies; \(outcomes.count)/6 deliveries")
            let mutual = replies.count >= 2 && replies.suffix(2).allSatisfy { $0.1.contains(config.stopSequence) } && replies[replies.count - 2].0 != replies.last?.0
            evidence.check("mutual-signoff", mutual ? .passed : .inconclusive, "Both participants must emit the sign-off in their final consecutive replies")
        }
        if scenario.behavior == .steering {
            evidence.check("held-focus", hold.observed && hold.passed ? .passed : .failed,
                           "Observed the live worker parked at the delivery gate with unchanged clipboard/focus, then resumed it")
            // Composer evidence establishes the actual two deliveries.
            let delivered = cleanup.filter { $0.1.contains(note) }.count
            evidence.check("steering-both-legs", delivered == 2 ? .passed : .failed, "Note found in \(delivered) observed pasted payloads; expected note and echo")
        }
        for target in [firstTarget, secondTarget] { evidence.capture(target, stage: "after-\(target.name.lowercased())", screenshots: options.screenshots) }
    }
}

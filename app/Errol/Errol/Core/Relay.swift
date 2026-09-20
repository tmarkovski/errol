// Message framing and the orchestration loop.

import ApplicationServices
import Foundation

// MARK: - Message framing

/// The ground rules' shipped text and the token it carries. The text is
/// editable in Settings (behind a warning — it defines how runs end), so it
/// lives as a template rather than an interpolated literal: the token stands
/// in for `config.stopSequence` and is substituted at send time, keeping the
/// marker itself a single source of truth however the prose is rewritten.
enum RelayRules {
    static let stopSequenceToken = "{{stopSequence}}"
    static let defaultTemplate = """
        This is an automated agent-to-agent conversation: your replies are relayed \
        to another AI assistant, and its replies are relayed back to you. The human \
        who set this up is not taking part in the conversation, though they may \
        occasionally interject a steering note to guide it — such notes arrive in \
        clearly marked sections, and both sides get to see them. Treat it as a real \
        multi-turn dialogue, not a one-shot answer: contribute incrementally and \
        leave room for the other assistant to build on your reply. When you want to \
        end the conversation, include {{stopSequence}} anywhere in a reply — \
        but only once the exchange has genuinely run its course; never initiate \
        the sign-off in your first reply. When the other assistant sends it, reply \
        with your own goodbye containing {{stopSequence}} — the conversation \
        closes once both sides have sent it. Replying with an empty message ends \
        the conversation immediately.
        """
}

/// Ground rules given to each agent once, at the start of its side of the
/// conversation. Everything after these two framing messages passes through
/// verbatim. Reads the template from `config` (copied there at Start), not
/// the settings store — this runs on the relay worker thread.
func relayRules() -> String {
    config.relayRulesTemplate
        .replacingOccurrences(of: RelayRules.stopSequenceToken,
                              with: config.stopSequence)
}

/// What the first agent receives: the rules plus the human's initial message.
func openingMessage() -> String {
    relayRules()
        + "\n\nThe initial message from the human user follows.\n\n---\n\n"
        + config.seed
}

/// What the second agent receives on its first turn: the rules, the human's
/// initial message, and the first agent's response to it.
func introMessage(firstReply: String, from otherName: String) -> String {
    relayRules() + """
    \n
    Below are the human's initial message and \(otherName)'s response to it, \
    so you have the full context. Continue the conversation by replying to \
    \(otherName).

    --- Initial message from the human ---

    \(config.seed)

    --- \(otherName)'s response ---

    \(firstReply)
    """
}

/// A steering note as first delivered, to the side about to reply. It reads
/// after the reply it rode in with, and describes the order of delivery —
/// the note is in this handoff, and the peer has not had it yet — rather
/// than what the human was doing when they wrote it: a note is queued while
/// the run keeps going, so nothing here may claim a pause. The echo on the
/// next turn is what closes the gap it names.
func steeringNoteSection(_ note: String, unseenBy otherName: String) -> String {
    """
    --- Steering note from the human ---

    The human submitted this steering note for the conversation. It is \
    included with this handoff and may concern earlier context. \(otherName) \
    has not yet received this note through the relay; it will be shared with \
    \(otherName) alongside your reply. Take it into account as you continue.

    \(note)
    """
}

/// A relayed reply, framed only when the human has steered. `noteAfter` is
/// a note taken at this handoff: it reads after the reply it was written
/// in response to. `noteBefore` is the note taken at the previous handoff,
/// echoed to the side whose reply it followed: it reads before the reply,
/// because that is the order they were delivered in — the sender had it in
/// their input before writing the reply below. With neither, the reply
/// passes through verbatim, which is the everyday case.
func relayedReply(_ reply: String, from otherName: String,
                  noteBefore: String? = nil, noteAfter: String? = nil) -> String {
    guard noteBefore != nil || noteAfter != nil else { return reply }
    var sections: [String] = []
    if let note = noteBefore {
        sections.append("""
        --- Steering note from the human ---

        This note was included in the input sent to \(otherName) before the \
        reply below. Take it into account as you continue.

        \(note)
        """)
    }
    sections.append("--- \(otherName)'s reply ---\n\n\(reply)")
    if let note = noteAfter {
        sections.append(steeringNoteSection(note, unseenBy: otherName))
    }
    return sections.joined(separator: "\n\n")
}

/// The text of one handoff — the reply and, when the human has steered, the
/// sections around it — assembled so the steering sections always travel
/// whole. The per-message cap (`config.maxChars`) protects usage, and under
/// it the reply is what gives way: it is cut to the room left after the
/// framing and the notes, never the other way around, because a note cut
/// short is a direction misread, while a reply cut short is marked as such
/// and the conversation carries on.
struct HandoffPayload {
    /// The side whose reply this is, named in the framing.
    var from: String
    /// The listener's first message carries the rules and the full context.
    var intro: Bool
    /// The note taken at the previous handoff, echoed before the reply.
    var echo: String?
    /// The note taken at this handoff, read after the reply.
    var note: String?

    /// The reply leaves its sender's icon in the console, and a fresh
    /// human note joins it from the prompt. An echo is already carried by
    /// the preceding actor, so it adds no second dot.
    func transferSources(from sender: Speaker) -> [TransferSource] {
        note == nil ? [.reply(sender)] : [.reply(sender), .userPrompt]
    }

    /// The whole thing around `reply`, cap or no cap.
    func assemble(reply: String) -> String {
        if intro {
            return introMessage(firstReply: reply, from: from)
                + (note.map { "\n\n" + steeringNoteSection($0, unseenBy: from) } ?? "")
        }
        return relayedReply(reply, from: from, noteBefore: echo, noteAfter: note)
    }

    /// The room the reply has under `cap` once the framing and the notes
    /// are in — negative when they alone exceed it.
    func replyRoom(cap: Int) -> Int {
        cap - assemble(reply: "").count
    }

    /// Whether the steering sections can travel whole under `cap` and still
    /// leave the reply at least its truncation mark.
    func carriesNotes(cap: Int) -> Bool {
        replyRoom(cap: cap) > relayTruncationMark.count
    }

    /// The text to send: the whole thing when it fits, otherwise the reply
    /// cut to the room left and marked as cut, so the message never exceeds
    /// `cap`. Callers judge the notes with `carriesNotes` first; if the
    /// framing alone leaves no room — a rules template longer than the cap
    /// — the plain cap applies as it always has.
    func text(reply: String, cap: Int) -> String {
        let whole = assemble(reply: reply)
        guard whole.count > cap else { return whole }
        let room = replyRoom(cap: cap) - relayTruncationMark.count
        guard room > 0 else { return String(whole.prefix(cap)) + relayTruncationMark }
        return assemble(reply: String(reply.prefix(room)) + relayTruncationMark)
    }
}

extension SteeringOutcome {
    /// What a send's outcome means for the note that rode it.
    init(_ send: SendOutcome) {
        switch send {
        case .confirmed: self = .delivered
        case .unconfirmed, .abandoned: self = .unconfirmed
        // A withheld send is retried with the note still in hand, so this
        // reading is only ever reached for a send that was not retried.
        case .refused, .withheld: self = .refused
        }
    }
}

// MARK: - Run

/// Which side of the relay a message belongs to. Only the opening message
/// needs naming — every turn after it goes to whoever did not just speak —
/// so this is what `config.first` holds and what the panel nominates before
/// a run starts.
enum Speaker: String {
    case chatgpt
    case claude
}

/// Per-side conversation state during a relay run, shown under each side's
/// readiness card in the panel.
enum ConversationStatus: String {
    case notStarted = "Not started"
    case chatting = "Chatting\u{2026}"
    /// Finished writing, with the reply detected but not yet delivered. Capture
    /// may still be waiting for the steering editor to release focus. A normal
    /// handoff leaves this state after capture and delivery; a hold can park
    /// here without implying the agent is still composing.
    case replied = "Reply ready"
    case waiting = "Waiting"
    case ended = "Conversation ended"
}

/// Optional observations used by the live harness. No alternate relay engine.
struct RelayInspection {
    var sendInspection: (TargetApp) -> SendInspection
    var delivered: (TargetApp, SendOutcome) -> Void = { _, _ in }
    var reply: (TargetApp, Int, String) -> Bool = { _, _, _ in true }
    var mayContinue: (TargetApp) -> Bool = { _ in true }
    var responsePoll: (TargetApp, ResponseSighting) -> Void = { _, _ in }
}

/// The whole relay run. Runs on a worker thread while the main thread serves
/// the panel's event loop. Ends with the report of how it went — posted as
/// `.ended` on the event stream before the return — which names a failed
/// start as such rather than leaving the panel to infer one.
///
/// Every operation that touches an app passes a gate. The steering hold
/// (RelayControl) is the human's; the blocks here are the apps': a side's
/// window minimized or behind another of the app's windows, unsent work in
/// the composer about to be pasted into, a conversation that moved on since
/// the reply the relay waited for. A block is checked before the control's
/// gate is taken — so a blocked run owns no focus operation and the
/// steering editor can open over it — and once more after, since the apps
/// can change in the gap. Nothing is typed, copied, or activated while
/// blocked; the run waits for the apps to come back, and Stop is answered
/// at every poll. What a bound window shows is not checked: the connection
/// is the window, and a conversation switched inside it is written into.
///
/// `bindings` are the destinations the human connected in setup, one per
/// side: they are checked again here, at the click, and never re-found. A
/// side without one is bound the way the readiness strip picks a window —
/// the path of a run started without setup, such as the harness's.
@discardableResult
func runRelay(chatgpt: TargetApp, claude: TargetApp,
              bindings prebound: [Speaker: BoundDestination] = [:],
              showTransfers: Bool = false,
              inspection: RelayInspection? = nil,
              operationCompleted: (Bool) -> Void = {
                  _ = relayControl.endOperation(continuingRun: $0)
              }) -> RunReport {
    // The app supplies a main-queue completion fence; command-line callers
    // have no steering editor and can release ownership directly.
    var operationActive = false
    func endOperation(continuingRun: Bool) {
        operationCompleted(continuingRun)
        operationActive = false
    }
    defer {
        if operationActive { endOperation(continuingRun: false) }
        relayControl.finishRun()
    }

    func side(_ target: TargetApp) -> Speaker {
        target.app == chatgpt.app ? .chatgpt : .claude
    }
    func name(_ side: Speaker) -> String {
        side == .chatgpt ? chatgpt.name : claude.name
    }

    // The block the run stands on, if any: one place for it to change, so
    // the panel and the log hear each change once.
    var block: RunBlock?
    func setBlock(_ new: RunBlock?) {
        guard new != block else { return }
        if let new {
            log(new.logLine(name: name(new.side)))
        } else if let old = block {
            log("Resumed — \(name(old.side)) is back as the relay needs it.")
        }
        block = new
        relayEvents.post(.blocked(new))
    }

    // What the report is made from.
    var captured = 0
    var signedOffBy: Speaker?
    func report(_ outcome: RunOutcome) -> RunReport {
        RunReport(outcome: outcome, repliesCaptured: captured, signedOffBy: signedOffBy, block: block)
    }
    func failedStart(_ reason: String) -> RunReport {
        log("ERROR: \(reason)")
        let failure = report(.failedStart(reason: reason))
        relayEvents.post(.ended(failure))
        return failure
    }

    // nil = no cap: the run ends on the conversation's own close (mutual
    // sign-off, empty reply, timeout, or Stop).
    let turnCap = config.limitTurns ? config.turns : nil
    if let turnCap, turnCap < 1 {
        return failedStart("The turn limit must be at least 1 when it is on.")
    }

    // Preflight: bind a destination in each app — an eligible chat window,
    // or (where the selectors allow it) an excluded-surface window with a
    // composer, e.g. a Claude Code session in Claude Desktop when no chat
    // conversation is open — with a composer that is readable, empty, and
    // not mid-reply. The readiness strip says the same things a few seconds
    // earlier; this is the check that counts, made at the click.
    var bindings: [Speaker: BoundDestination] = [:]
    for target in [chatgpt, claude] {
        let bound: BoundDestination
        if let chosen = prebound[side(target)] {
            // The human's choice, checked again now: still there and
            // reachable. A window minimized or gone is a refusal with the
            // reason, not a search for another.
            switch chosen.check() {
            case .same:
                bound = chosen
            case .hidden(let seen):
                return failedStart(RunBlock.windowHidden(side: side(target), seen: seen).startRefusal(name: target.name))
            case .lost(let detail):
                return failedStart("\(detail.prefix(1).uppercased())\(detail.dropFirst()). Connect \(target.name)'s conversation again.")
            }
        } else {
            guard let found = BoundDestination(target: target) else {
                log("Open a chat conversation in \(target.name) and try again. (Inspect shows how each window was classified.)")
                return failedStart("\(target.name) has no conversation window to relay into.")
            }
            bound = found
        }
        log(bound.bindingReport)
        if bound.identity.excluded {
            // Not a fault, and on the current single-window Claude Desktop not
            // even unusual: the Code world replaces the chat inside the one
            // window instead of opening beside it. With setup, the human
            // chose that window, named as a Code session under the icon.
            // Lead with what is being targeted either way.
            log("\(target.name): NOTE: relaying into a \(target.selectors.excludedSurfaceName ?? "non-chat") session. Everything relayed lands in that session.")
        }
        // From here every read of the side goes through the bound window.
        let scoped = bound.target
        guard inputArea(in: scoped) != nil else {
            return failedStart("\(target.name)'s chat window has no message field.")
        }
        if let refusal = deliveryBlock(for: composerState(in: scoped), side: side(target)) {
            return failedStart(refusal.startRefusal(name: target.name))
        }
        bindings[side(target)] = bound
    }
    func bound(_ target: TargetApp) -> BoundDestination { bindings[side(target)]! }
    // The targets the run drives are the bound ones: a finder asked about
    // `chatgpt` answers for the window the human chose.
    let chatgpt = bindings[.chatgpt]!.target
    let claude = bindings[.claude]!.target

    var speaker = config.first == .claude ? claude : chatgpt
    var listener = speaker.app == chatgpt.app ? claude : chatgpt

    var chatgptConversation = ConversationStatus.notStarted
    var claudeConversation = ConversationStatus.notStarted
    func setConversation(_ target: TargetApp, _ status: ConversationStatus) {
        if target.app == chatgpt.app { chatgptConversation = status }
        else { claudeConversation = status }
        relayEvents.post(.conversation(chatgpt: chatgptConversation,
                                       claude: claudeConversation))
    }
    /// One steering leg's outcome, to the panel.
    func reportSteering(_ leg: SteeringDelivery.Leg, _ note: String, to recipient: TargetApp,
                        turn: Int, outcome: SteeringOutcome) {
        let delivery = SteeringDelivery(leg: leg, note: note, recipient: side(recipient),
                                        turn: turn, outcome: outcome)
        relayEvents.post(.steering(delivery))
    }

    // MARK: Guards

    /// What a check of the apps found, before an operation.
    enum GuardVerdict {
        case clear
        case block(RunBlock)
        /// The destination is gone for good; the run ends on it.
        case lost(String)
    }
    func destinationGuard(_ target: TargetApp) -> GuardVerdict {
        let destination = bound(target)
        switch destination.check() {
        case .same: return .clear
        case .hidden(let seen): return .block(.windowHidden(side: side(target), seen: seen))
        case .lost(let detail): return .lost(detail)
        }
    }
    /// Before copying `target`'s reply: the destination, and that the reply
    /// the wait completed on is still the newest thing there. A count that
    /// rose, or an ordinal that advanced, means something was said since —
    /// a fall is virtualization unmounting older messages, not evidence.
    func captureGuard(_ target: TargetApp, expected: ResponseSighting) -> GuardVerdict {
        let destination = destinationGuard(target)
        guard case .clear = destination else { return destination }
        if hasStopButton(in: target) { return .block(.replying(side: side(target))) }
        let affordances = messageAffordances(in: target).count
        let ordinal = lastMessageOrdinal(in: target)
        if affordances > expected.affordances || (ordinal ?? 0) > (expected.lastOrdinal ?? 0) {
            trace("\(target.name): \(affordances) affordances, message \(ordinal.map(String.init) ?? "-") against the completed reply's \(expected.affordances)/\(expected.lastOrdinal.map(String.init) ?? "-")")
            return .block(.historyChanged(side: side(target)))
        }
        return .clear
    }
    /// Before pasting into `target`: the destination — in front of the
    /// app's other windows, raised there if need be, since the paste
    /// follows the key window — and a composer with nothing of the human's
    /// in it.
    func deliveryGuard(_ target: TargetApp) -> GuardVerdict {
        let destination = destinationGuard(target)
        guard case .clear = destination else { return destination }
        if let obstruction = bound(target).block(side: side(target), raising: true) {
            return .block(obstruction)
        }
        if let found = deliveryBlock(for: composerState(in: target), side: side(target)) {
            // Once per hold, not per poll: the gate asks again every second.
            if found != block {
                trace("\(target.name): the composer judged is \(composerDescription(in: target))")
            }
            return .block(found)
        }
        return .clear
    }

    /// Wait out a block, a poll at a time. false when Stop won.
    func standBy() -> Bool {
        for _ in 0..<5 {
            if relayControl.isCancelled { return false }
            usleep(200_000)
        }
        return true
    }

    enum GateResult {
        /// The operation is owned. A handoff's gate also carries the note
        /// it took — once; a re-entry after a withheld send carries none.
        case proceed(note: String?, unfit: String?)
        case end(RunOutcome)
    }

    /// Park until `target` can be touched for `kind`: no block, and the
    /// control's gate open. `carries` makes this a handoff gate — the
    /// mailbox is read through decideHandoff on the first control pass and
    /// the note kept through any later pass — and nil a plain one (capture,
    /// the opener, a re-entry). Cancel is answered at every poll and wins
    /// over both kinds of hold.
    func openGate(_ target: TargetApp, kind: FocusOperation, holdLine: String,
                  guardCheck: () -> GuardVerdict,
                  carries: ((String) -> Bool)? = nil) -> GateResult {
        var announcedHold = false
        var taken: (note: String?, unfit: String?)?
        func leaveHold() {
            if announcedHold {
                relayEvents.post(.holding(false))
                announcedHold = false
            }
        }
        while true {
            if relayControl.isCancelled { leaveHold(); return .end(.stopped) }
            switch guardCheck() {
            case .lost(let detail):
                leaveHold()
                return .end(.destinationLost(side: side(target), detail: detail))
            case .block(let found):
                setBlock(found)
                guard standBy() else { leaveHold(); return .end(.stopped) }
                continue
            case .clear:
                setBlock(nil)
            }
            let decision: HandoffDecision
            if let carries, taken == nil {
                decision = relayControl.decideHandoff(carries: carries)
            } else {
                switch relayControl.beginOperation(kind) {
                case .proceed: decision = .commit(note: nil, unfit: nil)
                case .hold: decision = .hold
                case .cancel: decision = .cancel
                }
            }
            switch decision {
            case .cancel:
                leaveHold()
                return .end(.stopped)
            case .hold:
                if !announcedHold {
                    log(holdLine)
                    relayEvents.post(.holding(true))
                    announcedHold = true
                }
                usleep(200_000)
                continue
            case .commit(let note, let unfit):
                if taken == nil { taken = (note, unfit) }
                if announcedHold { log("Resumed.") }
                leaveHold()
                operationActive = true
                // Owning the operation now: the apps may have changed during
                // the wait, and nothing is touched on a stale check.
                if case .clear = guardCheck() {
                    return .proceed(note: taken?.note, unfit: taken?.unfit)
                }
                endOperation(continuingRun: true)
                continue
            }
        }
    }

    /// The outcome a send that ended the run maps to.
    func sendFailure(_ outcome: SendOutcome, to target: TargetApp) -> RunOutcome {
        outcome == .abandoned ? .sendAbandoned(side: side(target)) : .sendRefused(side: side(target))
    }

    // MARK: The run

    // The turn being worked on and the note awaiting its echo live outside
    // the conversation itself: the tail reports against both.
    var turn = 0
    var steeringEcho: (note: String, turn: Int)?

    /// The conversation, from the opener to whatever ends it.
    func conduct() -> RunOutcome {
        let opener = openingMessage()
        log("Seeding \(speaker.name)...")
        var baseline = ResponseBaseline(affordances: 0, lastOrdinal: nil)
        var openingOutcome = SendOutcome.withheld
        while true {
            switch openGate(speaker, kind: .delivery, holdLine: "Paused — waiting before the opening message.",
                            guardCheck: { deliveryGuard(speaker) }) {
            case .end(let outcome): return outcome
            case .proceed: break
            }
            baseline = responseBaseline(in: speaker)
            openingOutcome = send(opener, to: speaker, sources: [.userPrompt], showTransfer: showTransfers,
                                  destination: bound(speaker),
                                  inspection: inspection?.sendInspection(speaker))
            if openingOutcome == .withheld {
                endOperation(continuingRun: true)
                guard standBy() else { return .stopped }
                continue
            }
            break
        }
        inspection?.delivered(speaker, openingOutcome)
        if openingOutcome.continuesRun {
            setConversation(speaker, .chatting)
            setConversation(listener, .waiting)
        }
        endOperation(continuingRun: openingOutcome.continuesRun)
        guard openingOutcome.continuesRun else { return sendFailure(openingOutcome, to: speaker) }
        baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)

        // A sign-off is relayed like any reply so the peer sees it; the run
        // ends when two consecutive replies carry the stop sequence.
        var lastReplyEnded = false

        // A steering note travels twice: with the handoff it lands on, and —
        // echoed — with the next one, so the side whose reply it followed
        // hears of it too. steeringEcho holds the note between those two
        // handoffs, with the turn it first rode, so the echo can be reported
        // against it.
        while true {
            turn += 1
            relayEvents.post(.turn(turn))
            // While the speaker's window shows another conversation, nothing
            // seen there is about this reply: observation is suspended and
            // the time does not count. A destination gone for good ends the
            // wait through mayContinue.
            var lost: String?
            let wait = waitForResponse(
                in: speaker, baseline: baseline,
                mayContinue: { lost == nil && inspection?.mayContinue(speaker) != false },
                blocked: {
                    switch destinationGuard(speaker) {
                    case .clear: return nil
                    case .block(let found): return found
                    case .lost(let detail):
                        lost = detail
                        return nil
                    }
                },
                onBlock: setBlock,
                onPoll: inspection.map { probe in { probe.responsePoll(speaker, $0) } })
            let expected: ResponseSighting
            switch wait {
            case .complete(let sighting):
                expected = sighting
            case .timedOut:
                log("Stopping: no response activity detected from \(speaker.name) for \(Int(config.timeout))s.")
                return .timedOut(side: side(speaker))
            case .ended:
                if let lost { return .destinationLost(side: side(speaker), detail: lost) }
                if relayControl.isCancelled {
                    log("Run stopped by user.")
                } else {
                    log("Verification stopped the relay while waiting for \(speaker.name).")
                }
                return .stopped
            }
            setConversation(speaker, .replied)

            // Capture: the gate, then the copy — retried from the gate when
            // the conversation went out of view inside the operation, ended
            // when the copy failed with the conversation in view.
            var reply: String?
            while reply == nil {
                switch openGate(speaker, kind: .capture,
                                holdLine: "Paused — \(speaker.name)'s reply is ready; waiting to copy it.",
                                guardCheck: { captureGuard(speaker, expected: expected) }) {
                case .end(let outcome):
                    if outcome == .stopped { log("Run stopped by user.") }
                    return outcome
                case .proceed: break
                }
                guard inspection?.mayContinue(speaker) != false else { return .stopped }
                reply = copyLastResponse(from: speaker,
                                         mayContinue: { bound(speaker).check() == .same })
                if reply == nil {
                    switch destinationGuard(speaker) {
                    case .clear:
                        log("Stopping: could not copy response from \(speaker.name) after a retry.")
                        return .copyFailed(side: side(speaker))
                    case .lost(let detail):
                        return .destinationLost(side: side(speaker), detail: detail)
                    case .block:
                        endOperation(continuingRun: true)
                    }
                }
            }
            guard let reply else { return .copyFailed(side: side(speaker)) }
            captured += 1

            if inspection?.reply(speaker, turn, reply) == false {
                log("Verification stopped the relay after inspecting turn \(turn).")
                return .stopped
            }

            let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedReply.isEmpty {
                setConversation(speaker, .ended)
                log("\(speaker.name) ended the conversation (empty reply).")
                return .emptyReply(side: side(speaker))
            }
            let signedOff = trimmedReply.localizedCaseInsensitiveContains(config.stopSequence)
            if signedOff {
                setConversation(speaker, .ended)
                if lastReplyEnded {
                    log("\(speaker.name) ended the conversation too — both sides have signed off.")
                    signedOffBy = nil
                    return .completed
                }
                signedOffBy = side(speaker)
                log("\(speaker.name) ended the conversation; relaying the sign-off so \(listener.name) can close out.")
            } else {
                signedOffBy = nil
            }
            lastReplyEnded = signedOff

            log("Turn \(turn)\(turnCap.map { "/\($0)" } ?? ""): \(speaker.name) -> \(listener.name) (\(reply.count) chars)")

            if let turnCap, turn >= turnCap {
                log("Turn cap reached.")
                return .turnLimitReached
            }
            endOperation(continuingRun: true)

            // The handoff's text: the listener's first message carries the rules
            // and full context; every later relay is the other agent's reply,
            // untouched unless a steering note frames it. The echo goes in
            // first, and one that cannot travel whole is dropped and reported
            // before the fresh note is judged against the room that is left.
            var payload = HandoffPayload(from: speaker.name, intro: turn == 1,
                                         echo: steeringEcho?.note, note: nil)
            if let echo = steeringEcho, !payload.carriesNotes(cap: config.maxChars) {
                log("The echoed steering note is too long to travel whole with this handoff; not sharing it.")
                payload.echo = nil
                reportSteering(.echo, echo.note, to: listener, turn: turn, outcome: .tooLong)
                steeringEcho = nil
            }

            // Delivery: the gate parks the run here — the reply is safely
            // captured and nothing has been typed into the listener yet.
            // Hold, end, or go is one decision made under the mailbox's lock,
            // so a claim from the panel either wins the note and the hold
            // together or loses both (RelayControl.decideHandoff). A send
            // withheld at the keystroke comes back to the gate with the note
            // already in hand.
            var noteTaken = false
            var outcome = SendOutcome.withheld
            while true {
                let carries: ((String) -> Bool)? = noteTaken ? nil : { note in
                    var trial = payload
                    trial.note = note
                    return trial.carriesNotes(cap: config.maxChars)
                }
                switch openGate(listener, kind: .delivery,
                                holdLine: "Paused — holding \(speaker.name)'s captured reply before it reaches \(listener.name).",
                                guardCheck: { deliveryGuard(listener) }, carries: carries) {
                case .end(let ending):
                    if ending == .stopped { log("Run stopped by user.") }
                    return ending
                case .proceed(let note, let unfit):
                    guard !noteTaken else { break }
                    noteTaken = true
                    if let unfit {
                        log("The human's steering note is too long to travel whole with this handoff; not sending it.")
                        reportSteering(.note, unfit, to: listener, turn: turn, outcome: .tooLong)
                    }
                    // A note queued while the reply was being written — or while
                    // the run stood held — rides this handoff, after the reply it
                    // answers. Committing it is announced before the paste, so
                    // the panel lets go of a note the courier already holds.
                    if let note {
                        payload.note = note
                        log("Relaying the human's steering note with this handoff.")
                        relayEvents.post(.steeringCommitted(note: note, recipient: side(listener), turn: turn))
                    }
                }
                baseline = responseBaseline(in: listener)
                outcome = send(payload.text(reply: reply, cap: config.maxChars), to: listener,
                               sources: payload.transferSources(from: side(speaker)), showTransfer: showTransfers,
                               destination: bound(listener),
                               inspection: inspection?.sendInspection(listener))
                if outcome == .withheld {
                    endOperation(continuingRun: true)
                    guard standBy() else { return .stopped }
                    continue
                }
                break
            }
            inspection?.delivered(listener, outcome)
            if let note = payload.note {
                reportSteering(.note, note, to: listener, turn: turn, outcome: SteeringOutcome(outcome))
            }
            if let echo = payload.echo {
                reportSteering(.echo, echo, to: listener, turn: turn, outcome: SteeringOutcome(outcome))
            }
            // The note is echoed at the next handoff unless nothing was typed
            // at all; a send that may have landed still earns its echo.
            if let note = payload.note, outcome != .refused {
                steeringEcho = (note, turn)
            } else {
                steeringEcho = nil
            }
            if outcome.continuesRun {
                if !signedOff { setConversation(speaker, .waiting) }
                setConversation(listener, .chatting)
            }
            endOperation(continuingRun: outcome.continuesRun)
            guard outcome.continuesRun else { return sendFailure(outcome, to: listener) }
            baseline = absorbEchoIntoBaseline(in: listener, preSend: baseline)
            swap(&speaker, &listener)
        }
    }

    let outcome = conduct()

    // Close terminal capture paths before any editor grant can be delivered.
    if operationActive { endOperation(continuingRun: false) }
    relayControl.finishRun()

    // What the run left undelivered: a note still queued never rode a
    // handoff, and an echo still pending never reached the side whose reply
    // the note followed. Both are said outright, so nothing is assumed.
    if let left = relayControl.takeSteering() {
        reportSteering(.note, left, to: listener, turn: turn, outcome: .runEnded)
    }
    if let echo = steeringEcho {
        reportSteering(.echo, echo.note, to: listener, turn: echo.turn + 1, outcome: .runEnded)
    }

    // A side frozen mid-state by a cap, stop, or error is not in a
    // conversation anymore; only a real sign-off survives as "ended".
    if chatgptConversation != .ended { setConversation(chatgpt, .notStarted) }
    if claudeConversation != .ended { setConversation(claude, .notStarted) }

    let ending = report(outcome)
    relayEvents.post(.ended(ending))
    log("Done.")
    return ending
}

// Message framing: the ground rules, the opening and intro messages, and the
// capped handoff each reply travels in: pure text, apart from the loop.

import Foundation

// MARK: - Message framing

/// The ground rules' text and the token it carries. The text is kept as a
/// template rather than an interpolated literal so the marker has one
/// source of truth: the token stands in for `config.stopSequence` and is
/// substituted at send time, however the prose is rewritten.
///
/// The rules are the framing and then how the conversation ends: the
/// sign-off, or, when only Stop ends the run, the human ending it.
enum RelayRules {
    static let stopSequenceToken = "{{stopSequence}}"
    static let framing = """
        This is an automated agent-to-agent conversation: your replies are relayed \
        to another AI assistant, and its replies are relayed back to you. The human \
        who set this up is not taking part in the conversation, though they may \
        occasionally interject a steering note to guide it — such notes arrive in \
        clearly marked sections, and both sides get to see them. Treat it as a real \
        multi-turn dialogue, not a one-shot answer: contribute incrementally and \
        leave room for the other assistant to build on your reply.
        """
    static let signOff = """
        When you want to end the conversation, include {{stopSequence}} anywhere \
        in a reply — but only once the exchange has genuinely run its course; never initiate \
        the sign-off in your first reply. When the other assistant sends it, reply \
        with your own goodbye containing {{stopSequence}} — the conversation \
        closes once both sides have sent it. Replying with an empty message ends \
        the conversation immediately.
        """
    /// For a run that only Stop ends. No marker is mentioned, so neither side
    /// reaches for one out of habit.
    static let humanEnds = """
        There is no sign-off in this conversation: the human will end it when \
        they choose. Until then, keep the exchange going — build on each other's \
        replies, and when a thread runs dry, take up a new angle on the topic \
        rather than wrapping up or saying goodbye.
        """
    static let defaultTemplate = framing + " " + signOff
}

/// Ground rules given to each agent once, at the start of its side of the
/// conversation. Everything after these two framing messages passes through
/// verbatim.
func relayRules() -> String {
    let template = config.ending.endsOnSignOff
        ? RelayRules.defaultTemplate
        : RelayRules.framing + " " + RelayRules.humanEnds
    return template.replacingOccurrences(of: RelayRules.stopSequenceToken,
                                         with: config.stopSequence)
}

/// Whether a reply signs off: the chosen ending acts on the sign-off, and
/// the reply carries the marker in any letter case. With the run ending
/// only on Stop, the marker is text like any other.
func isSignOff(_ reply: String) -> Bool {
    config.ending.endsOnSignOff && reply.localizedCaseInsensitiveContains(config.stopSequence)
}

/// The reply with every copy of the marker taken out, in any letter case.
func strippingSignOff(_ reply: String) -> String {
    reply.replacingOccurrences(of: config.stopSequence, with: "", options: .caseInsensitive)
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
    /// — it falls back to the plain cap, which keeps the prefix and adds
    /// the mark after it, so that message runs over by the mark's length,
    /// as the plain cap always has.
    func text(reply: String, cap: Int) -> String {
        let whole = assemble(reply: reply)
        guard whole.count > cap else { return whole }
        let room = replyRoom(cap: cap) - relayTruncationMark.count
        guard room > 0 else { return truncatedForRelay(whole, cap: cap) }
        return assemble(reply: String(reply.prefix(room)) + relayTruncationMark)
    }
}

extension SteeringOutcome {
    /// What a send's outcome means for the note that rode it.
    init(_ send: SendOutcome) {
        switch send {
        case .confirmed: self = .delivered
        case .unconfirmed, .abandoned: self = .unconfirmed
        // A withheld send, or one the app would not come to the front
        // for, is retried with the note still in hand, so this reading is
        // only ever reached for a send that was not retried.
        case .refused, .withheld, .notInFront: self = .refused
        }
    }
}

/// What a cut message ends with, so the peer sees it was cut rather than a
/// silent ellipsis.
let relayTruncationMark = "\n\n[truncated by relay]"

/// The per-message length cap, applied before pasting — the protection
/// (with the turn cap) against two chatty models burning through usage.
/// The plain cap keeps the beginning; a handoff carrying steering notes is
/// assembled to fit under it first (HandoffPayload), so the notes travel
/// whole and this never cuts one.
func truncatedForRelay(_ text: String, cap: Int = config.maxChars) -> String {
    guard text.count > cap else { return text }
    return String(text.prefix(cap)) + relayTruncationMark
}

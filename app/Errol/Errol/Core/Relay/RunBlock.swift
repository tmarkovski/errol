// The holds a run stands in while it stays recoverable, and every line that
// names one: the pause headline and recovery, a failed start, the log, the summary.

// MARK: - Holds

/// Why a run is standing still while it stays recoverable. Distinct from
/// the steering hold, which the human asks for, and from the outcome the
/// run ends with: a block is a condition observed in the apps, cleared by
/// the apps, and a run can stand in one while the steering editor is open.
enum RunBlock: Equatable {
    /// The side's window is minimized or behind another of the app's
    /// windows: nothing can be read from or typed into it until it shows.
    case windowHidden(side: Speaker, seen: String)
    /// The side's composer holds unsent work.
    case draft(side: Speaker, characters: Int)
    case attachments(side: Speaker, count: Int)
    /// The side is producing a reply the relay did not ask for.
    case replying(side: Speaker)
    /// The side's composer cannot be read, so it cannot be known empty.
    case composerUnreadable(side: Speaker)
    /// The side's conversation has more messages than the reply the relay
    /// waited for: something was said since.
    case historyChanged(side: Speaker)
    /// The side's app would not come to the front for the relay — a
    /// keystroke lands in the frontmost app, and the copy button writes
    /// the clipboard only from a focused window — so the human brings it
    /// forward, and the relay goes on from where it stood.
    case notInFront(side: Speaker)
    /// A dialog stands over the side's conversation — Claude's image viewer
    /// is one — and hides it from the tree: nothing can be read from or
    /// typed into it until the human closes the dialog (coveringDialog).
    /// `by` is the dialog's name, empty when it has none.
    case covered(side: Speaker, by: String)

    var side: Speaker {
        switch self {
        case .windowHidden(let side, _), .draft(let side, _), .attachments(let side, _),
             .replying(let side), .composerUnreadable(let side), .historyChanged(let side),
             .notInFront(let side), .covered(let side, _):
            return side
        }
    }

    /// A covering dialog as the lines name it: by its own name where it
    /// has one, else as a dialog — at the start of a sentence, and after
    /// "Close".
    private static func cover(_ by: String) -> (subject: String, object: String) {
        by.isEmpty ? ("A dialog", "the dialog") : ("\u{201C}\(by)\u{201D}", "\u{201C}\(by)\u{201D}")
    }

    /// The one line that says what is wrong.
    func headline(names: SideNames) -> String {
        let name = names[side]
        switch self {
        case .windowHidden: return "Paused: \(name)'s window isn't showing"
        case .draft: return "Paused: \(name) has an unsent draft"
        case .attachments: return "Paused: \(name) has an unsent attachment"
        case .replying: return "Paused: \(name) is replying to something else"
        case .composerUnreadable: return "Paused: \(name)'s composer can't be read"
        case .historyChanged: return "Paused: \(name)'s conversation moved on"
        case .notInFront: return "Paused: \(name) couldn't be brought to the front"
        case .covered: return "Paused: \(name)'s conversation is covered"
        }
    }

    /// What clears it, and that Stop is there.
    func recovery(names: SideNames) -> String {
        let name = names[side]
        switch self {
        case .windowHidden(_, let seen):
            return "It is \(seen). Bring it back to continue, or Stop. Errol resumes when it is showing again."
        case .draft(_, let characters):
            return "Finish or clear the \(characters)-character draft in \(name) to continue, or Stop."
        case .attachments(_, let count):
            return "Send or remove the \(count == 1 ? "attachment" : "\(count) attachments") in \(name) to continue, or Stop."
        case .replying:
            return "Errol waits for \(name) to finish, then continues if the conversation is unchanged. Stop is available."
        case .composerUnreadable:
            return "Click into \(name)'s message field so it can be read, or Stop."
        case .historyChanged:
            return "Messages were added in \(name) since the reply Errol was waiting for. Errol cannot tell what to relay now; Stop, or undo the change to continue."
        case .notInFront:
            return "Click \(name)'s window to bring it to the front. Errol continues once it is in front, or Stop."
        case .covered(_, let by):
            return "Close \(Self.cover(by).object) in \(name) to continue, or Stop. Errol resumes once the conversation is showing."
        }
    }

    /// Why a run does not start on this, for the failed-start report: the
    /// condition and what to do before pressing Send again.
    func startRefusal(name: String) -> String {
        switch self {
        case .windowHidden(_, let seen):
            return "\(name)'s window is \(seen). Bring it back, then send again."
        case .draft(_, let characters):
            return "\(name) has an unsent draft (\(characters) characters). Finish or clear it, then send again."
        case .attachments(_, let count):
            return "\(name) has \(count) unsent attachment\(count == 1 ? "" : "s"). Send or remove \(count == 1 ? "it" : "them"), then send again."
        case .replying:
            return "\(name) is still replying. Wait for it to finish, then send again."
        case .composerUnreadable:
            return "\(name)'s message field can't be read. Click into it, then send again."
        case .historyChanged:
            return "\(name)'s conversation changed. Send again."
        case .notInFront:
            return "\(name) couldn't be brought to the front. Click its window, then send again."
        case .covered(_, let by):
            return "\(Self.cover(by).subject) is open over \(name)'s conversation. Close it, then send again."
        }
    }

    /// The log line, with the apps' own names.
    func logLine(name: String) -> String {
        switch self {
        case .windowHidden(_, let seen):
            return "Paused — \(name)'s window is \(seen). Bring it back to continue, or Stop."
        case .draft(_, let characters):
            return "Paused — \(name) has an unsent draft (\(characters) characters). Finish or clear it to continue, or Stop."
        case .attachments(_, let count):
            return "Paused — \(name) has \(count) unsent attachment\(count == 1 ? "" : "s"). Send or remove \(count == 1 ? "it" : "them") to continue, or Stop."
        case .replying:
            return "Paused — \(name) is replying to something the relay did not send; waiting for it to finish."
        case .composerUnreadable:
            return "Paused — \(name)'s composer cannot be read, so it cannot be known to be empty."
        case .historyChanged:
            return "Paused — \(name)'s conversation has messages the relay did not expect since its reply completed."
        case .notInFront:
            return "Paused — \(name) would not come to the front. Click its window to bring it forward; the relay continues from there, or Stop."
        case .covered(_, let by):
            return "Paused — \(Self.cover(by).subject) is open over \(name)'s conversation, which hides it from Errol. Close it to continue, or Stop."
        }
    }
}

/// The composer's state as a block on delivering to `side`, nil when it
/// admits a paste.
func deliveryBlock(for state: ComposerState, side: Speaker) -> RunBlock? {
    switch state {
    case .empty: return nil
    case .draft(let characters): return .draft(side: side, characters: characters)
    case .attachments(let count): return .attachments(side: side, count: count)
    case .replying: return .replying(side: side)
    case .unreadable: return .composerUnreadable(side: side)
    case .covered(let by): return .covered(side: side, by: by)
    }
}

extension RunBlock {
    /// The block as a clause in the summary's context: what the run stood
    /// on when Stop was pressed.
    func contextClause(names: SideNames) -> String {
        let name = names[side]
        switch self {
        case .windowHidden: return "\(name)'s window was hidden"
        case .draft: return "\(name) had an unsent draft"
        case .attachments: return "\(name) had an unsent attachment"
        case .replying: return "\(name) was replying to something else"
        case .composerUnreadable: return "\(name)'s composer could not be read"
        case .historyChanged: return "\(name)'s conversation had moved on"
        case .notInFront: return "\(name) would not come to the front"
        case .covered: return "\(name)'s conversation was covered"
        }
    }
}

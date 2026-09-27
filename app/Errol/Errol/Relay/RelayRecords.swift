// The value records the model keeps for the console: the log's lines, the
// steering note in flight and its receipt, and the transcript's entries.

import Foundation

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// A note the worker has committed to a handoff and is pasting now: out
/// of the field, not yet with an outcome. The design is
/// docs/design-proposals/steering/the-note-stays-put.md, as revised at its
/// end: Pause to steer opens the field and holds the run, Return sends the
/// note and lets the run go, the head says where the note is.
struct SteeringInFlight: Equatable {
    var note: String
    /// The recipient's app name.
    var recipient: String
    var turn: Int
}

/// The record of a note's journey, the head's line under the turn line
/// once the note has left the field, kept until the next note or New
/// session. Every field is what was observed, so "shared" is never assumed.
struct SteeringReceipt: Equatable {
    enum Outcome: Equatable {
        /// Delivery confirmed: paste verified and a submission signal seen.
        case sent
        /// Submitted, no confirming signal.
        case unconfirmed
        /// Never reached the recipient, for the reason given.
        case notSent(SteeringOutcome)
        /// A draft the run ended on, never queued.
        case neverQueued
    }
    enum Echo: Equatable {
        case shared(turn: Int)
        case unconfirmed
        case notShared
    }
    var note: String
    /// The recipient's app name; nil for a draft that never went anywhere.
    var recipient: String?
    var turn: Int?
    var outcome: Outcome
    /// The echo to the other side, once its handoff has happened or been
    /// ruled out; nil while it is still ahead.
    var echo: Echo?
}

/// One line of the run's transcript under the console (PerchTranscript):
/// what a reply said, or a note the human sent, in the order the
/// conversation took them in.
struct TranscriptEntry: Identifiable, Equatable {
    enum Author: Equatable {
        case side(Speaker)
        case human
    }
    /// Where a note stands. Its echo to the other side is the receipt's
    /// to tell (SteeringReceipt), once the run has ended.
    enum Delivery: Equatable {
        case sending, sent, unconfirmed, notSent
    }
    let id: Int
    let author: Author
    /// What the line says: the model's sentence on a reply once it has
    /// one, and the reply's opening before that and wherever the model
    /// cannot write one; a short reply whole; a note as it was sent.
    var text: String
    /// Whether the text is the reply's own words rather than a sentence
    /// on it, which the transcript sets apart (PerchTranscript).
    var verbatim = false
    /// Whether the model is still writing the reply's sentence.
    var summarizing = false
    /// Whether the reply carried the sign-off, which the transcript marks
    /// after the text: a sentence on the reply's words alone would not
    /// say so.
    var signsOff = false
    /// For a note, whom it went to and where it stands; nil for a reply.
    var recipient: Speaker?
    var delivery: Delivery?
}

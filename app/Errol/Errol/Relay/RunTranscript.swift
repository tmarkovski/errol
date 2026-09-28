// The run's transcript for the window under the console (PerchTranscript):
// its lines, the model's sentences that replace a reply's opening as they
// come, and the marks on a note's line as its handoff goes. Its own model
// rather than a part of RelayController, since none of it reads the run's
// other state: the controller decides when a reply or a note belongs on
// it (only while a run is on) and when it clears, and the transcript keeps
// the lines and the tasks writing them.

import Foundation
import Observation

@Observable
final class RunTranscript {
    /// The lines, oldest first: each reply once it is in hand, each note
    /// once it sets off. Kept whole through the ending, and cleared at the
    /// next start and by New topic.
    private(set) var entries: [TranscriptEntry] = []
    /// What writes a reply's line; the live model, or a stand-in in previews.
    @ObservationIgnored var summarizeReply: @Sendable (String) async -> String? = { await ReplySummarizer.gist($0) }
    @ObservationIgnored private var gistTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextID = 0

    /// A reply in hand goes on the transcript at once, as its opening (or
    /// whole, when it is short), and the model's sentence takes the
    /// opening's place when it comes. A sign-off is marked on the line; a
    /// reply that is nothing else is only that.
    func replyCaptured(_ reply: String, from side: Speaker) {
        let signsOff = isSignOff(reply)
        let text = strippingSignOff(reply)
        let flat = ReplySummarizer.flatten(text)
        guard !flat.isEmpty else {
            if signsOff { append(.side(side), text: "Signs off") }
            return
        }
        let summarizing = ReplySummarizer.needsGist(flat)
        let id = append(.side(side), text: flat, verbatim: true, summarizing: summarizing,
                        signsOff: signsOff)
        guard summarizing else { return }
        let summarize = summarizeReply
        gistTasks[id] = Task { @MainActor [weak self] in
            let gist = await summarize(text)
            guard !Task.isCancelled, let self else { return }
            gistTasks[id] = nil
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            if let gist {
                entries[index].text = gist
                entries[index].verbatim = false
            }
            entries[index].summarizing = false
        }
    }

    @discardableResult
    func append(_ author: TranscriptEntry.Author, text: String, verbatim: Bool = false,
                summarizing: Bool = false, signsOff: Bool = false,
                recipient: Speaker? = nil, delivery: TranscriptEntry.Delivery? = nil) -> Int {
        let id = nextID
        nextID += 1
        entries.append(TranscriptEntry(id: id, author: author, text: text, verbatim: verbatim,
                                       summarizing: summarizing, signsOff: signsOff,
                                       recipient: recipient, delivery: delivery))
        return id
    }

    func clear() {
        gistTasks.values.forEach { $0.cancel() }
        gistTasks.removeAll()
        entries.removeAll()
    }

    /// A note's line: on the transcript as it sets off, and marked with
    /// how its handoff went. A note that never set off (too long to
    /// travel whole) still goes on, marked as not sent, so the transcript
    /// does not lose it; one the run ended on is the ending's to report.
    func note(_ delivery: SteeringDelivery) {
        guard delivery.leg == .note else { return }
        let state: TranscriptEntry.Delivery
        switch delivery.outcome {
        case .delivered: state = .sent
        case .unconfirmed: state = .unconfirmed
        case .refused, .tooLong, .runEnded: state = .notSent
        }
        if let index = sendingNoteIndex {
            entries[index].delivery = state
        } else if delivery.outcome != .runEnded {
            append(.human, text: ReplySummarizer.flatten(delivery.note),
                   recipient: delivery.recipient, delivery: state)
        }
    }

    /// A note still in flight when the run ends never got its outcome,
    /// which is what unconfirmed means; its line says so, as its receipt
    /// does.
    func markSendingUnconfirmed() {
        if let index = sendingNoteIndex { entries[index].delivery = .unconfirmed }
    }

    /// The line of the note on its way, if one is.
    private var sendingNoteIndex: Int? {
        entries.lastIndex(where: { $0.author == .human && $0.delivery == .sending })
    }
}

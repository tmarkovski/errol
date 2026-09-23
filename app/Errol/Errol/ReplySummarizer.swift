// One short sentence on what a reply said, for the run's transcript under
// the console (PerchTranscript): written by the on-device model once the
// reply is in hand, while the other side writes its answer, so the wait
// costs the run nothing. The transcript names who replied with the app's
// mark, and the sentence has no subject of its own: asked to name the
// speaker, the model credited replies to the wrong side, and took a
// reply's "you argued…" for the other side's position. A reply that fits
// the transcript's line as it is shows whole; one the model cannot sum up
// (unavailable, declined, too slow) shows its opening instead. Nothing
// leaves the Mac.

import Foundation
import FoundationModels

enum ReplySummarizer {
    /// Replies up to this long, once flattened, are shown whole: they fit
    /// the transcript's line as they are, and a sentence on one would be
    /// as long as the reply.
    static let wholeLimit = 90

    /// Whether a flattened reply is long enough to need the model's line.
    static func needsGist(_ flat: String) -> Bool { flat.count > wholeLimit }

    /// The line, or nil when the model is unavailable, declines, answers
    /// with nothing usable, or takes longer than the transcript should wait.
    static func gist(_ reply: String) async -> String? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, SystemLanguageModel.default.isAvailable else { return nil }
        let excerpt = Self.excerpt(text)
        var options = GenerationOptions()
        options.maximumResponseTokens = 60
        let instructions = Self.instructions
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                // Summing up is a transformation of text the human already
                // has, which is what the permissive guardrails are for: a
                // reply about something sensitive is still a reply to sum up.
                let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                let session = LanguageModelSession(model: model, instructions: instructions)
                guard let answer = try? await session.respond(to: excerpt, options: options).content else {
                    return nil
                }
                return clean(answer)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(12))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Tried against replies of every length in the logs, and on topics far
    /// from them. The model copies whatever verbs it is shown: with
    /// concession examples every line began "Agrees" or "Concedes"; shown
    /// no verbs it lost the form (imperatives, "The message…") and the
    /// point; shown forty it settled on "Suggests". A short list grouped by
    /// the kind of move a message makes has it name the move first, so the
    /// verb follows the reply. Asked for the message it answers as well, it
    /// mixed the two up. One sentence is asked for; clean keeps the first.
    private static let instructions = """
        You write a one-line gist of one message in a discussion, for a \
        person glancing at it. Say the message's main move, what it mainly \
        does, in one sentence of at most fifteen words. A message may make a \
        claim (Holds that..., Argues that..., Warns that..., Doubts \
        that...), a proposal (Proposes..., Suggests...), a plan (Lays \
        out..., Lists...), a question (Asks whether..., Asks for...), an \
        example (Gives the example of...), a decision (Settles on..., \
        Drops...), a pushback (Rejects..., Insists that...), or, when it \
        does nothing else, an agreement (Agrees...). Lead with the move that \
        carries most of the message, not with what it grants along the way. \
        Start with a present-tense verb and leave out the subject. When the \
        message pushes back on a view, say what it holds instead, never the \
        view it answers. Say nothing the message does not say. Do not quote \
        it, and do not add a label, a preamble, or a closing remark.
        """

    /// What the model reads: the whole reply when it fits the context
    /// comfortably, otherwise its opening and its close, which is where
    /// replies put their position and their question.
    static func excerpt(_ text: String) -> String {
        let head = 6000, tail = 1500
        guard text.count > head + tail else { return text }
        return String(text.prefix(head)) + "\n\n[\u{2026}]\n\n" + String(text.suffix(tail))
    }

    /// The model's answer as the transcript's line: its first sentence,
    /// should it write more than the one asked for, unquoted, capitalized,
    /// without a closing full stop (like the topic line), and of a length
    /// the transcript can show. Nil when nothing is left.
    static func clean(_ answer: String) -> String? {
        var line = answer.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let quotes = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        line = line.trimmingCharacters(in: quotes)
        if let end = line.range(of: #"[.!?]\s"#, options: .regularExpression) {
            line = String(line[..<end.lowerBound])
        }
        while line.hasSuffix(".") { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.prefix(1).uppercased() + line.dropFirst()
        if line.count > 200 { line = String(line.prefix(199)) + "\u{2026}" }
        return line.isEmpty ? nil : line
    }

    /// A reply, or a note, as one line of plain text: code blocks out,
    /// markdown's marks off the words, the lines joined. Capped well past
    /// what the transcript shows, which truncates it.
    static func flatten(_ text: String) -> String {
        var lines: [String] = []
        var inCode = false
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCode.toggle()
                continue
            }
            if inCode { continue }
            for pattern in [#"^#{1,6}\s+"#, #"^>\s?"#, #"^[-*+]\s+"#, #"^\d+[.)]\s+"#] {
                line = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            for mark in ["**", "__", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(line) }
        }
        let flat = lines.joined(separator: " ")
        return flat.count > 400 ? String(flat.prefix(400)) : flat
    }
}

// One sentence on what a conversation is about, for the console's top
// line (PerchTopicLine): written by the on-device model from the prompt
// the human sent, once a run has started. An enhancement over the prompt's
// own first line, which the console shows until the sentence arrives and
// instead when none does: the model is unavailable on some Macs, declines
// some benign prompts outright, and is given a bounded time to answer.
// Nothing leaves the Mac, and nothing from the apps' replies goes in.

import Foundation
import FoundationModels

enum TopicSummarizer {
    /// The one sentence, or nil when the model is unavailable, declines,
    /// answers with nothing usable, or takes longer than the console
    /// should wait.
    static func summarize(_ prompt: String) async -> String? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, SystemLanguageModel.default.isAvailable else { return nil }
        // A topic is in the opening; a long prompt is cut so the model
        // reads a few hundred tokens at most and answers in a second or two.
        let excerpt = String(text.prefix(2400))
        var options = GenerationOptions()
        options.maximumResponseTokens = 60
        let instructions = Self.instructions
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                guard let answer = try? await session.respond(to: excerpt, options: options).content else {
                    return nil
                }
                return clean(answer)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static let instructions = """
        You write the topic line for a discussion between two AI assistants. \
        You are given the opening prompt a person wrote to start it. Answer \
        with one short sentence, under fifteen words, saying what the \
        discussion is about. Use plain words. Do not quote the prompt, do \
        not address anyone, and do not add a preamble or a closing remark.
        """

    /// The model's answer as one line: the first line it wrote, unquoted,
    /// without a trailing full stop, and of a length the console can show.
    /// Nil when nothing is left.
    static func clean(_ answer: String) -> String? {
        var line = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        line = line.trimmingCharacters(in: quotes)
        while line.hasSuffix(".") { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.count > 160 { line = String(line.prefix(159)) + "\u{2026}" }
        return line.isEmpty ? nil : line
    }
}

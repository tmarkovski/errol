// How dictated words land in a prompt field, kept pure so the contract
// tests pin it. The microphone and the model live in the app target
// (VoiceInput.swift, SpeechAnalyzerTranscriber.swift); this file is only
// the text: what one listening has heard, how it joins what the field
// already held, and the fillers a written prompt does without.

import Foundation

/// What the microphone has heard in one listening. `settled` is text the
/// model is done with; `forming` is its current guess at the words after
/// it, replaced whole by each update until it settles in turn.
struct HeardSpeech: Equatable, Sendable {
    var settled = ""
    var forming = ""

    /// Everything heard, as the field shows it.
    var text: String { settled + forming }
}

/// One listening's hold on a field: the text it continues from, and what
/// it last wrote there. A field that no longer reads as that was changed
/// by someone else (typed into, cleared, sent), and the listening lets go
/// instead of writing over the change.
struct VoiceSplice: Equatable {
    let base: String
    private(set) var written: String

    init(base: String) {
        self.base = base
        written = base
    }

    /// The field's new text with everything heard after its base, or nil
    /// when the field no longer holds what this listening last wrote.
    mutating func apply(_ heard: HeardSpeech, over current: String) -> String? {
        guard current == written else { return nil }
        written = VoiceText.join(base, heard.text)
        return written
    }
}

enum VoiceText {
    /// Hesitations that carry nothing in a written prompt. The system's
    /// dictation model drops them; SpeechTranscriber writes them down as
    /// spoken, set off with commas (", um,"), so they go here.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "erm"]

    /// The field's text with the heard words after it: one space between
    /// the two, unless the field is empty or already ends in whitespace.
    static func join(_ base: String, _ heard: String) -> String {
        let words = clean(heard)
        guard !words.isEmpty else { return base }
        let gap = base.isEmpty || base.last?.isWhitespace == true ? "" : " "
        return base + gap + words
    }

    /// The heard words without fillers, one space between each. A filler's
    /// commas go with it; the end of a sentence it carried moves onto the
    /// word before; and one that opened a sentence hands its capital on.
    static func clean(_ heard: String) -> String {
        var kept: [String] = []
        var capitalizeNext = false
        for token in heard.split(whereSeparator: \.isWhitespace).map(String.init) {
            let core = token.trimmingCharacters(in: .punctuationCharacters)
            guard fillers.contains(core.lowercased()) else {
                kept.append(capitalizeNext ? token.prefix(1).uppercased() + token.dropFirst() : token)
                capitalizeNext = false
                continue
            }
            guard var previous = kept.popLast() else {
                capitalizeNext = true
                continue
            }
            if endsSentence(previous) { capitalizeNext = true }
            if previous.hasSuffix(",") { previous.removeLast() }
            if endsSentence(token), !endsSentence(previous) { previous.append(token.last!) }
            if !previous.isEmpty { kept.append(previous) }
        }
        return kept.joined(separator: " ")
    }

    private static func endsSentence(_ token: String) -> Bool {
        token.last.map { ".?!".contains($0) } ?? false
    }
}

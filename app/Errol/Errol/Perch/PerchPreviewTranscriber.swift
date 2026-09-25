// The canvases' microphone: a press of the mic "hears" one scripted
// sentence, a word at a time, the way SpeechTranscriber's forming words
// arrive, and settles it when the mic is pressed again or the sentence
// runs out. Nothing opens the real microphone.

#if DEBUG
import Foundation

final class PerchPreviewTranscriber: VoiceTranscriber {
    static let script = "Keep it to three rounds each, and end with one recommendation you both sign."

    private var playing: Task<Void, Never>?
    private var stream: AsyncThrowingStream<HeardSpeech, Error>.Continuation?
    private var heard = HeardSpeech()

    func listen() async throws -> AsyncThrowingStream<HeardSpeech, Error> {
        let (words, continuation) = AsyncThrowingStream<HeardSpeech, Error>.makeStream()
        stream = continuation
        heard = HeardSpeech()
        playing = Task { @MainActor [weak self] in
            for word in Self.script.split(separator: " ") {
                try? await Task.sleep(for: .milliseconds(260))
                guard let self, !Task.isCancelled else { return }
                heard.forming += " \(word)"
                continuation.yield(heard)
            }
            await self?.finish()
        }
        return words
    }

    func finish() async {
        playing?.cancel()
        heard.settled += heard.forming
        heard.forming = ""
        stream?.yield(heard)
        stream?.finish()
        stream = nil
    }

    func cancel() async {
        playing?.cancel()
        stream?.finish()
        stream = nil
    }
}
#endif

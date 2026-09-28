// Speaking into the prompt box: the mic button beside Start relay and
// Resume fills the field it stands under with what the human says. The
// words come from Apple's on-device SpeechTranscriber (macOS 26), so
// nothing leaves the Mac and Errol ships no model: the system keeps the
// language assets, shared with Notes and Dictation. A probe on Sep 25 2026
// transcribed twelve seconds of speech in half a second on an M1 Max,
// with no speech-recognition prompt; only the microphone asks.
//
// The model behind the button is VoiceInput. It talks to a VoiceTranscriber,
// which the relay engine hands out: the live one in the app
// (SpeechAnalyzerTranscriber.swift), a scripted one in the canvases
// (PerchPreviewTranscriber) that never opens the microphone. Another
// model (Parakeet, Whisper) would be one more conformer.
// How the heard words join the field is Core/Console/VoiceText.swift.

import Foundation
import Observation

/// Hears the microphone and says what it heard.
protocol VoiceTranscriber: AnyObject {
    /// Opens the microphone and starts hearing, once it may: the first call
    /// asks for the microphone, and may fetch the language's model. Each
    /// update carries everything heard since the start. The stream finishes
    /// when the listening is over and throws when it broke off.
    func listen() async throws -> AsyncThrowingStream<HeardSpeech, Error>
    /// Closes the microphone. The words still forming settle, and the
    /// stream finishes after them.
    func finish() async
    /// Closes the microphone and drops whatever had not settled; the stream
    /// finishes without another update.
    func cancel() async
}

/// The mic button's model: whether a listening is under way, and why the
/// last one could not start or broke off. A listening writes into one
/// field through the two closures it was started with, after whatever the
/// field held, and lets go of it the moment someone else changes it —
/// typing takes the field back. Main thread only, like RelayController.
@Observable
final class VoiceInput {
    enum Phase: Equatable {
        case idle
        /// Asking for the microphone, or readying the model.
        case starting
        case listening
        /// The microphone is closed; the last words are settling.
        case finishing
    }

    private(set) var phase = Phase.idle
    /// Why the last listening could not start or broke off; cleared by the
    /// next one.
    private(set) var problem: String?

    @ObservationIgnored private let transcriber: VoiceTranscriber
    /// Advanced by each start and each cancel, so a listening that was
    /// called off stops writing even if an update was already on its way.
    @ObservationIgnored private var generation = 0

    init(transcriber: VoiceTranscriber) {
        self.transcriber = transcriber
    }

    var isActive: Bool { phase != .idle }

    /// The button: start hearing into the field, or finish the listening
    /// under way. A press while it starts calls it off.
    func toggle(read: @escaping () -> String, write: @escaping (String) -> Void) {
        switch phase {
        case .idle: start(read: read, write: write)
        case .starting: cancel()
        case .listening: finish()
        case .finishing: break
        }
    }

    /// Closes the microphone and lets the last words settle into the field.
    func finish() {
        guard phase == .listening else { return }
        phase = .finishing
        Task { @MainActor [transcriber] in await transcriber.finish() }
    }

    /// Closes the microphone now. The field keeps what it shows, forming
    /// words included, so what is sent is what was on screen; nothing more
    /// lands in it. Called when the field is sent, cleared, or goes away,
    /// which also retires the last listening's problem.
    func cancel() {
        problem = nil
        guard phase != .idle else { return }
        generation += 1
        phase = .idle
        Task { @MainActor [transcriber] in await transcriber.cancel() }
    }

    private func start(read: @escaping () -> String, write: @escaping (String) -> Void) {
        problem = nil
        phase = .starting
        generation += 1
        let generation = generation
        var splice = VoiceSplice(base: read())
        Task { @MainActor [weak self, transcriber] in
            do {
                let heard = try await transcriber.listen()
                guard let self, self.generation == generation else { return await transcriber.cancel() }
                phase = .listening
                for try await update in heard {
                    guard self.generation == generation else { return }
                    guard let text = splice.apply(update, over: read()) else { return cancel() }
                    write(text)
                }
            } catch {
                guard let self, self.generation == generation else { return }
                problem = error.localizedDescription
            }
            guard let self, self.generation == generation else { return }
            phase = .idle
        }
    }
}

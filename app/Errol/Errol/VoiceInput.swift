// Speaking into the prompt box: the mic button beside Start relay and
// Resume fills the field it stands under with what the human says. The
// words come from Apple's on-device SpeechTranscriber (macOS 26), so
// nothing leaves the Mac and Errol ships no model: the system keeps the
// language assets, shared with Notes and Dictation. A probe on Sep 25 2026
// transcribed twelve seconds of speech in half a second on an M1 Max,
// with no speech-recognition prompt; only the microphone asks.
//
// The model behind the button is VoiceInput. It talks to a VoiceTranscriber,
// which the relay engine hands out: the live one here in the app, a scripted
// one in the canvases (PerchPreviewTranscriber) that never opens the
// microphone. Another model (Parakeet, Whisper) would be one more conformer.
// How the heard words join the field is Core/VoiceText.swift.

import AVFoundation
import Foundation
import Observation
import Speech

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

enum VoiceError: LocalizedError {
    case microphoneDenied
    case noMicrophone
    case unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Errol can\u{2019}t use the microphone. Allow it in System Settings \u{203A} Privacy & Security \u{203A} Microphone."
        case .noMicrophone:
            "No microphone is available."
        case .unsupportedLanguage:
            "Speech isn\u{2019}t available in your Mac\u{2019}s language yet."
        }
    }
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

// MARK: - The live transcriber

/// SpeechTranscriber fed from the default input device. The microphone
/// runs through AVAudioEngine and is converted to the analyzer's format by
/// hand; on macOS 27, CaptureInputSequenceProvider does both.
///
/// VoiceInput calls in from the main actor, and the methods run where they
/// are called, so its state is only touched there. A cancel can still land
/// while a listen waits on the permission or the model, so each listen
/// holds a session number and gives up once a cancel has moved it on.
final class SpeechAnalyzerTranscriber: VoiceTranscriber {
    private var audio: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var session = 0

    func listen() async throws -> AsyncThrowingStream<HeardSpeech, Error> {
        session += 1
        let session = session
        let superseded = { [weak self] in self?.session != session }
        guard await Self.microphoneAllowed() else { throw VoiceError.microphoneDenied }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw VoiceError.unsupportedLanguage
        }
        // The progressive preset reports forming words as they are heard,
        // which is what lets the field fill while the human talks.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Nil when the system already has the language, as it does for
        // English on a Mac that has used Dictation or Notes transcription.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.unsupportedLanguage
        }

        // Results are read from before the first buffer, so none is missed.
        let heard = AsyncThrowingStream<HeardSpeech, Error> { continuation in
            let reading = Task {
                var heard = HeardSpeech()
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            heard.settled += text
                            heard.forming = ""
                        } else {
                            heard.forming = text
                        }
                        continuation.yield(heard)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        if superseded() { throw CancellationError() }
        let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream()

        let audio = AVAudioEngine()
        let microphone = audio.inputNode.outputFormat(forBus: 0)
        guard microphone.channelCount > 0, microphone.sampleRate > 0,
              let converter = AVAudioConverter(from: microphone, to: format) else {
            throw VoiceError.noMicrophone
        }
        // Priming would shift every buffer's timestamps against the audio.
        converter.primeMethod = .none
        audio.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone) { buffer, _ in
            if let converted = Self.convert(buffer, with: converter, to: format) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
        audio.prepare()
        do {
            try audio.start()
        } catch {
            audio.inputNode.removeTap(onBus: 0)
            throw error
        }
        // Held before the last wait, so a cancel during it closes them.
        self.audio = audio
        self.analyzer = analyzer
        self.input = input
        try await analyzer.start(inputSequence: inputs)
        if superseded() { throw CancellationError() }
        return heard
    }

    func finish() async {
        closeMicrophone()
        let analyzer = analyzer
        self.analyzer = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() async {
        session += 1
        closeMicrophone()
        let analyzer = analyzer
        self.analyzer = nil
        await analyzer?.cancelAndFinishNow()
    }

    private func closeMicrophone() {
        audio?.inputNode.removeTap(onBus: 0)
        audio?.stop()
        audio = nil
        input?.finish()
        input = nil
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        default: false
        }
    }

    /// One microphone buffer in the analyzer's format.
    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0, let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || converted.frameLength == 0 ? nil : converted
    }
}

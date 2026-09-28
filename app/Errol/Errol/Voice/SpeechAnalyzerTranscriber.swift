// The live VoiceTranscriber: Apple's SpeechTranscriber fed from the default
// microphone, and the errors a listening can fail with. Its own file so
// VoiceInput.swift keeps to the mic button's model, clear of AVFoundation.

import AVFoundation
import Foundation
import Speech

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

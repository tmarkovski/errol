// One answer from the on-device model, bounded in time: the call the
// topic line (TopicSummarizer) and the transcript's reply lines
// (ReplySummarizer) both make, differing only in the guardrails, the
// token budget and how long they wait. Each summarizer keeps its own
// instructions, excerpt and cleanup; what is shared is the availability
// check and the race against the clock. It lives in the app target, not
// Core, so ErrolKit does not link FoundationModels. Nothing leaves the Mac.

import Foundation
import FoundationModels

enum OnDeviceModel {
    /// The model's raw answer to `prompt`, or nil when the model is
    /// unavailable, declines, fails, or takes longer than `timeout`.
    static func respond(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        timeout: Duration,
        guardrails: SystemLanguageModel.Guardrails = .default
    ) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        var options = GenerationOptions()
        options.maximumResponseTokens = maxTokens
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let model = SystemLanguageModel(guardrails: guardrails)
                let session = LanguageModelSession(model: model, instructions: instructions)
                return try? await session.respond(to: prompt, options: options).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

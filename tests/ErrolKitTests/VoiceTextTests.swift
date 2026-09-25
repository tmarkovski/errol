import XCTest
@testable import ErrolKit

final class VoiceTextTests: XCTestCase {
    // MARK: Fillers

    /// The shapes SpeechTranscriber wrote in the probe of Sep 25 2026: a
    /// filler set off with commas, one opening a sentence, and "Ah", which
    /// can be a word and stays.
    func testFillersGoWithTheirCommas() {
        XCTAssertEqual(VoiceText.clean("Is there a, um, native transcription we can add?"),
                       "Is there a native transcription we can add?")
        XCTAssertEqual(VoiceText.clean("Ah, I just want you to. Um, investigate the viability of it."),
                       "Ah, I just want you to. Investigate the viability of it.")
    }

    func testAFillerOpeningTheTextHandsOnItsCapital() {
        XCTAssertEqual(VoiceText.clean("Um, have Claude look at the sidebar."), "Have Claude look at the sidebar.")
    }

    func testAFillerMidSentenceCapitalizesNothing() {
        XCTAssertEqual(VoiceText.clean("I think, Um, yes"), "I think yes")
    }

    func testASentenceEndCarriedByAFillerMovesOntoTheWordBefore() {
        XCTAssertEqual(VoiceText.clean("look at the sidebar, uh."), "look at the sidebar.")
        XCTAssertEqual(VoiceText.clean("Done. Um."), "Done.")
    }

    func testWordsThatOnlyStartLikeFillersStay() {
        XCTAssertEqual(VoiceText.clean("Umbrella pricing, umpteen tiers"), "Umbrella pricing, umpteen tiers")
    }

    func testOnlyFillersLeaveNothing() {
        XCTAssertEqual(VoiceText.clean(" um, uh "), "")
    }

    // MARK: Joining the field

    func testHeardWordsFollowTheFieldWithOneSpace() {
        XCTAssertEqual(VoiceText.join("Compare pricing.", " Keep it short."), "Compare pricing. Keep it short.")
        XCTAssertEqual(VoiceText.join("Compare pricing.\n", "Keep it short."), "Compare pricing.\nKeep it short.")
        XCTAssertEqual(VoiceText.join("", " Keep it short."), "Keep it short.")
    }

    func testNothingHeardLeavesTheFieldAsItWas() {
        XCTAssertEqual(VoiceText.join("Compare pricing", ""), "Compare pricing")
        XCTAssertEqual(VoiceText.join("Compare pricing", " um "), "Compare pricing")
    }

    // MARK: The splice

    /// Forming words are replaced as they change and settle in place; the
    /// field's own text is never touched.
    func testUpdatesRewriteOnlyWhatWasHeard() {
        var splice = VoiceSplice(base: "Topic:")
        var field = "Topic:"
        field = splice.apply(HeardSpeech(forming: " Tell Claude"), over: field)!
        XCTAssertEqual(field, "Topic: Tell Claude")
        field = splice.apply(HeardSpeech(forming: " Tell Claude to stop"), over: field)!
        XCTAssertEqual(field, "Topic: Tell Claude to stop")
        field = splice.apply(HeardSpeech(settled: " Tell Claude to stop hedging.", forming: " Then"), over: field)!
        XCTAssertEqual(field, "Topic: Tell Claude to stop hedging. Then")
    }

    /// Typing, clearing, or sending the field between updates takes it
    /// back: the listening writes nothing more over it.
    func testAChangedFieldIsLeftAlone() {
        var splice = VoiceSplice(base: "")
        let written = splice.apply(HeardSpeech(forming: " Tell Claude"), over: "")!
        XCTAssertNil(splice.apply(HeardSpeech(forming: " Tell Claude to"), over: written + "!"))
        XCTAssertNil(splice.apply(HeardSpeech(forming: " Tell Claude to"), over: ""))
    }
}

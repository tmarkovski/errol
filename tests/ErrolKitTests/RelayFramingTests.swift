// The relay's pure message plumbing: the framing each side receives, the
// per-message length cap, and the stop-sequence contract. These tests mutate
// the global config, so they restore it after each run.

import XCTest
@testable import ErrolKit

final class RelayFramingTests: XCTestCase {
    var savedConfig: Config!

    override func setUp() {
        super.setUp()
        savedConfig = config
    }

    override func tearDown() {
        config = savedConfig
        super.tearDown()
    }

    func testOpeningMessageCarriesRulesAndSeed() {
        config.seed = "Plan a trip to Skye."
        let opener = openingMessage()
        XCTAssertTrue(opener.contains(config.stopSequence),
                      "the rules must tell the agent how to end the conversation")
        XCTAssertTrue(opener.hasSuffix(config.seed),
                      "the seed passes through verbatim, after the framing")
    }

    func testIntroMessageCarriesSeedReplyAndPeerName() {
        config.seed = "Plan a trip to Skye."
        let intro = introMessage(firstReply: "Start with the Quiraing.", from: "ChatGPT")
        XCTAssertTrue(intro.contains(config.stopSequence))
        XCTAssertTrue(intro.contains(config.seed))
        XCTAssertTrue(intro.contains("Start with the Quiraing."))
        XCTAssertTrue(intro.contains("replying to ChatGPT"))
    }

    func testLengthCapTruncatesAndMarks() {
        config.maxChars = 100
        let long = String(repeating: "x", count: 500)
        let capped = truncatedForRelay(long)
        XCTAssertTrue(capped.hasPrefix(String(repeating: "x", count: 100)))
        XCTAssertTrue(capped.hasSuffix("[truncated by relay]"),
                      "the peer must see that the message was cut, not a silent ellipsis")
        XCTAssertEqual(capped.count, 100 + "\n\n[truncated by relay]".count)
        XCTAssertEqual(truncatedForRelay("short"), "short",
                       "messages under the cap pass through untouched")
    }

    func testRulesDiscourageEarlySignoff() {
        // Both models signed off after one reply each in the first live run —
        // the single-shot habit: answer completely, feel finished, reach for
        // the marker. The standing rules must push back on that for every
        // purpose, so both framed openings carry pacing language. The seed
        // can still tighten pacing per purpose (the live test does).
        for framing in [openingMessage(), introMessage(firstReply: "hi", from: "ChatGPT")] {
            XCTAssertTrue(framing.contains("not a one-shot answer"),
                          "the rules must frame this as a multi-turn dialogue")
            XCTAssertTrue(framing.contains("never initiate the sign-off in your first reply"),
                          "\"initiate\" is deliberate: reciprocating a peer's sign-off in a first reply must stay allowed")
            XCTAssertTrue(framing.contains("run its course"),
                          "ending must be tied to the exchange being exhausted, not to having answered once")
        }
    }

    func testDefaultEndConditionIsTheSignoff() {
        // A fresh Config must leave the turn cap off: runs end on the
        // conversation's own close (mutual sign-off, empty reply, timeout,
        // or Stop), and the cap is the opt-in "Limit turns" checkbox.
        let defaults = Config()
        XCTAssertFalse(defaults.limitTurns)
        XCTAssertEqual(defaults.turns, 10, "the cap's value when enabled")
    }

    func testStopSequenceDetectionIsCaseInsensitive() {
        // The run loop checks replies with localizedCaseInsensitiveContains;
        // a model lowercasing the marker must still end the conversation.
        let reply = "It was a pleasure. [[end-conversation]]"
        XCTAssertTrue(reply.localizedCaseInsensitiveContains(config.stopSequence))
        XCTAssertFalse("no marker here".localizedCaseInsensitiveContains(config.stopSequence))
    }

    // MARK: Steering

    func testRulesAnticipateSteering() {
        // The rules once said the human takes no part at all; a steering
        // note landing under that frame reads as the peer role-playing the
        // human. Both sides' opening framing must leave the door ajar.
        for framing in [openingMessage(), introMessage(firstReply: "hi", from: "ChatGPT")] {
            XCTAssertTrue(framing.contains("steering note"),
                          "the rules must anticipate the human's interjections")
        }
    }

    func testRelayedReplyPassesThroughUnframed() {
        // The everyday case: no steering anywhere near, no framing at all.
        XCTAssertEqual(relayedReply("Just the reply.", from: "Claude"), "Just the reply.")
    }

    func testFreshNoteReadsAfterTheReplyItFollowed() {
        // The note was written in response to the reply, so the recipient
        // reads them in that order — and learns the sender has not.
        let framed = relayedReply("On the Quiraing.", from: "Claude",
                                  noteAfter: "Focus on the geology.")
        let reply = framed.range(of: "On the Quiraing.")!
        let note = framed.range(of: "Focus on the geology.")!
        XCTAssertTrue(reply.lowerBound < note.lowerBound,
                      "the note came after the reply, so it must read after it")
        XCTAssertTrue(framed.contains("Claude has not yet received this note"))
        XCTAssertTrue(framed.contains("alongside your reply"),
                      "the recipient must know the note travels on with its own reply")
        XCTAssertFalse(framed.localizedCaseInsensitiveContains("paused"),
                       "a note is queued while the run keeps going; the framing must not claim a pause")
    }

    func testEchoedNoteReadsBeforeTheReplyWrittenInItsLight() {
        // A turn later the note reaches the side whose reply it followed —
        // ahead of the peer's reply, because the peer read it first.
        let framed = relayedReply("Fine: the geology.", from: "Claude",
                                  noteBefore: "Focus on the geology.")
        let note = framed.range(of: "Focus on the geology.")!
        let reply = framed.range(of: "Fine: the geology.")!
        XCTAssertTrue(note.lowerBound < reply.lowerBound,
                      "the note preceded the reply, so it must read before it")
        XCTAssertTrue(framed.contains("included in the input sent to Claude before the reply below"),
                      "the recipient must know the peer had the note before replying")
        XCTAssertFalse(framed.localizedCaseInsensitiveContains("paused"),
                       "the framing describes the order of delivery, not what the human was doing")
    }

    func testBackToBackNotesKeepTheirOrderAroundTheReply() {
        // Steered at two handoffs running: the echoed note preceded the
        // reply, the fresh one followed it.
        let framed = relayedReply("Basalt columns, then.", from: "Claude",
                                  noteBefore: "Focus on the geology.",
                                  noteAfter: "Now compare it to the Cuillin.")
        let echoed = framed.range(of: "Focus on the geology.")!
        let reply = framed.range(of: "Basalt columns, then.")!
        let fresh = framed.range(of: "Now compare it to the Cuillin.")!
        XCTAssertTrue(echoed.lowerBound < reply.lowerBound)
        XCTAssertTrue(reply.lowerBound < fresh.lowerBound)
    }

    func testIntroCarriesSteeringSectionWhenAppended() {
        // A note posted while the opener was composing rides the intro:
        // the run loop appends the same marked section the later frames use.
        let payload = introMessage(firstReply: "Start at the Quiraing.", from: "ChatGPT")
            + "\n\n" + steeringNoteSection("Keep it to three days.", unseenBy: "ChatGPT")
        let reply = payload.range(of: "Start at the Quiraing.")!
        let note = payload.range(of: "Keep it to three days.")!
        XCTAssertTrue(reply.lowerBound < note.lowerBound)
        XCTAssertTrue(payload.contains("--- Steering note from the human ---"))
    }

    func testSteeringMailboxTakeConsumesAndResetDiscards() {
        // One note per handoff: take hands the note over exactly once, and
        // a run starting fresh can discard a note that never found its
        // handoff.
        let control = RelayControl()
        XCTAssertNil(control.takeSteering())
        control.postSteering("Focus on the geology.")
        XCTAssertEqual(control.takeSteering(), "Focus on the geology.")
        XCTAssertNil(control.takeSteering(), "a taken note must not ride two handoffs")
        control.postSteering("Leftover from a dead run.")
        control.reset()
        XCTAssertNil(control.takeSteering())
    }

    func testHandoffDecisionTakesTheNoteInTheSameStepAsTheFlags() {
        // Hold, end, or go is one locked decision, and go takes the note in
        // the same step — the gap between checking the pause and taking the
        // note is where a claim could win the mailbox and lose the handoff.
        let control = RelayControl()
        control.postSteering("Focus on the geology.")
        XCTAssertEqual(control.requestHold(), .now)
        XCTAssertEqual(control.decideHandoff { _ in true }, .hold)
        XCTAssertTrue(control.hasSteering, "a held handoff leaves the note where it is")
        control.finishSteering(note: "Focus on the geology.")
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "Focus on the geology.", unfit: nil))
        XCTAssertFalse(control.hasSteering, "committing takes the note")
        XCTAssertFalse(control.endOperation(continuingRun: true))
        XCTAssertEqual(control.decideHandoff { _ in true }, .commit(note: nil, unfit: nil))
        XCTAssertFalse(control.endOperation(continuingRun: true))
        control.postSteering("Too long.")
        XCTAssertEqual(control.decideHandoff { _ in false },
                       .commit(note: nil, unfit: "Too long."),
                       "a note that cannot travel whole is taken off and reported, never trimmed")
        XCTAssertFalse(control.hasSteering)
        XCTAssertFalse(control.endOperation(continuingRun: true))
        control.postSteering("Never rides.")
        XCTAssertEqual(control.requestHold(), .now)
        control.cancel()
        XCTAssertEqual(control.decideHandoff { _ in true }, .cancel, "cancel wins over hold")
        XCTAssertTrue(control.hasSteering, "a cancelled handoff takes nothing")
    }

    func testClaimSteeringWinsTheNoteAndHoldOrWaitsForCommittedDelivery() {
        // Edit & pause: the panel takes the note back and asks for the hold
        // in one step. A claim the worker beat opens empty after delivery.
        let control = RelayControl()
        control.postSteering("Focus on the geology.")
        let claim = control.claimSteering()
        XCTAssertEqual(claim.note, "Focus on the geology.")
        XCTAssertEqual(claim.grant, .now)
        XCTAssertTrue(control.isPaused, "a won claim holds the next handoff in the same step")
        XCTAssertEqual(control.decideHandoff { _ in true }, .hold)
        control.reset()
        control.postSteering("Now compare it to the Cuillin.")
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "Now compare it to the Cuillin.", unfit: nil))
        let lost = control.claimSteering()
        XCTAssertNil(lost.note, "the worker committed first")
        XCTAssertEqual(lost.grant, .afterOperation)
        XCTAssertTrue(control.isPaused)
        XCTAssertTrue(control.endOperation(continuingRun: true))
    }

    func testHandoffPayloadKeepsSteeringSectionsWholeUnderTheCap() {
        // The reply gives way under the cap, never the notes: a note cut
        // short is a direction misread.
        config.seed = "Plan a trip to Skye."
        let note = String(repeating: "Focus on the geology. ", count: 20)
        let echo = String(repeating: "Keep it to three days. ", count: 20)
        let reply = String(repeating: "Basalt columns. ", count: 500)
        let payload = HandoffPayload(from: "Claude", intro: false, echo: echo, note: note)
        let cap = 2000
        XCTAssertTrue(payload.carriesNotes(cap: cap))
        let text = payload.text(reply: reply, cap: cap)
        XCTAssertLessThanOrEqual(text.count, cap,
                                 "the assembled message respects the cap, so send's own cap is a no-op on it")
        XCTAssertTrue(text.contains(note), "the fresh note travels whole")
        XCTAssertTrue(text.contains(echo), "the echoed note travels whole")
        XCTAssertTrue(text.contains(relayTruncationMark), "the reply is what was cut, and says so")
        XCTAssertTrue(text.contains("Basalt columns."), "some of the reply survives")
        XCTAssertEqual(payload.text(reply: "Short.", cap: cap), payload.assemble(reply: "Short."),
                       "untouched when it all fits")
    }

    func testHandoffPayloadRefusesANoteItCannotCarryWhole() {
        let long = String(repeating: "x", count: 3000)
        var payload = HandoffPayload(from: "Claude", intro: false, echo: nil, note: long)
        XCTAssertFalse(payload.carriesNotes(cap: 2000),
                       "a note longer than the cap has no handoff that carries it whole")
        payload.intro = true
        XCTAssertFalse(payload.carriesNotes(cap: 2000))
        payload.note = nil
        XCTAssertTrue(payload.carriesNotes(cap: 2000), "without the note the same handoff carries")
    }

    func testSteeringOutcomeFollowsTheSendOutcome() {
        XCTAssertEqual(SteeringOutcome(.confirmed), .delivered)
        XCTAssertEqual(SteeringOutcome(.unconfirmed), .unconfirmed)
        XCTAssertEqual(SteeringOutcome(.abandoned), .unconfirmed,
                       "a foreground lost after a possible submission is unconfirmed, not failed")
        XCTAssertEqual(SteeringOutcome(.refused), .refused)
        XCTAssertTrue(SendOutcome.unconfirmed.continuesRun)
        XCTAssertFalse(SendOutcome.abandoned.continuesRun)
        XCTAssertFalse(SendOutcome.refused.continuesRun)
    }
}

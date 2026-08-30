// The canned conversation shapes behind the panel's picker. The bodies are
// prompts, so these tests pin their contracts rather than their prose: every
// template must reference the topic appended below it, describe its own
// ending, and leave the sign-off mechanics to the relay rules.

import XCTest
@testable import ErrolKit

final class ConversationTemplateTests: XCTestCase {
    func testTemplateNames() {
        XCTAssertEqual(defaultConversationTemplates.map(\.name),
                       ["Brainstorm", "Debate", "Code review", "Adversary"],
                       "the picker's display order; renames ripple into the README's Controls section")
    }

    func testComposedAppendsTopicAfterTheBody() {
        let template = defaultConversationTemplates[0]
        XCTAssertEqual(template.composed(topic: "cheap ways to soundproof a door"),
                       template.body + "\n\ncheap ways to soundproof a door")
    }

    func testEveryTemplateReferencesTheAppendedTopic() {
        for template in defaultConversationTemplates {
            XCTAssertTrue(template.body.contains("below"),
                          "\(template.name): the body must point at the topic composed below it")
            XCTAssertFalse(template.topicPrompt.isEmpty,
                           "\(template.name): the panel's topic field needs its placeholder")
        }
    }

    func testEveryTemplateDescribesItsOwnEnding() {
        // Purpose-specific pacing is why templates exist: on top of the
        // standing rules' baseline (never sign off in a first reply), each
        // body must say what "done" means for its shape, so the models have
        // a reason to keep going and a reason to stop.
        for template in defaultConversationTemplates {
            XCTAssertTrue(template.body.localizedCaseInsensitiveContains("end"),
                          "\(template.name): the body must describe when the conversation is over")
        }
    }

    func testTemplatesLeaveTheMarkerMechanicsToTheRules() {
        for template in defaultConversationTemplates {
            XCTAssertFalse(template.body.localizedCaseInsensitiveContains(config.stopSequence),
                           "\(template.name): relayRules owns the sign-off mechanics; a copy here would drift")
        }
    }

    func testDefaultRulesTemplateCarriesTheToken() {
        // The token appears once per mention of the sign-off: the initiating
        // side and the reply. Rendering must resolve every occurrence.
        XCTAssertEqual(RelayRules.defaultTemplate
            .components(separatedBy: RelayRules.stopSequenceToken).count - 1, 2)
    }

    func testRelayRulesRenderSubstitutesEveryToken() {
        let rendered = relayRules()
        XCTAssertTrue(rendered.contains(config.stopSequence))
        XCTAssertFalse(rendered.contains(RelayRules.stopSequenceToken),
                       "an unresolved token would tell the agents to type the placeholder")
    }
}

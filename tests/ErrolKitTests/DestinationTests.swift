// What identifies a conversation on each surface, read from the recorded
// fixtures, and how the binding judges a later reading against it: a route
// is binding, a specific title is a hint, a generic one is nothing, and a
// fresh chat gaining either is adoption. The fixture facts are the ones
// the first-run proposal tabulated (docs/design-proposals/first-run-
// usability): /chat/<uuid> and /epitaxy/<id> name a conversation, /new and
// /project/<uuid> do not, and ChatGPT exposes no conversation URL at all.

import XCTest
@testable import ErrolKit

final class DestinationTests: XCTestCase {
    private let claude = config.claudeSelectors
    private let chatgpt = config.chatgptSelectors

    private func identity(_ fixture: String, window index: Int = 0,
                          selectors: AppSelectors) throws -> DestinationIdentity {
        let windows = loadFixture(fixture)
        let window = try XCTUnwrap(windows.indices.contains(index) ? windows[index] : nil,
                                   "\(fixture) has no window \(index)")
        return DestinationIdentity(scan: scanWindow(window, selectors: selectors), selectors: selectors)
    }

    // MARK: Identity from the fixtures

    func testClaudeChatConversationIsIdentifiedByItsRoute() throws {
        let identity = try identity("claude-chat-conversation", selectors: claude)
        XCTAssertEqual(identity.route, "/chat/8f3c2a91-77aa-4bfa-9f21-0d6e2b9d5c44")
        XCTAssertEqual(identity.title, "Errol brand naming")
        XCTAssertFalse(identity.titleIsGeneric)
        XCTAssertEqual(identity.surface, "Chat")
        XCTAssertFalse(identity.excluded)
        XCTAssertTrue(identity.isDistinct)
        XCTAssertEqual(identity.displayName, "\u{201C}Errol brand naming\u{201D}")
    }

    func testClaudeCodeSessionIsIdentifiedByItsRouteBehindAGenericTitle() throws {
        let identity = try identity("claude-code-collapsed", selectors: claude)
        XCTAssertEqual(identity.route, "/epitaxy/a1b2c3d4-5e6f-7089-9abc-def012345678")
        XCTAssertTrue(identity.titleIsGeneric, "the Code window is titled Claude")
        XCTAssertTrue(identity.excluded)
        XCTAssertEqual(identity.surface, "Code")
        XCTAssertTrue(identity.isDistinct)
        XCTAssertEqual(identity.displayName, "the Code conversation")
    }

    func testFreshClaudeChatHasNothingToTellItApart() throws {
        // The real home capture: /new, titled Claude. Nothing distinguishes
        // it from any other unnamed chat, and the binding report says so.
        let identity = try identity("claude-chat-home", selectors: claude)
        XCTAssertNil(identity.route, "/new is every fresh chat, not a conversation")
        XCTAssertTrue(identity.titleIsGeneric)
        XCTAssertEqual(identity.surface, "Chat")
        XCTAssertFalse(identity.isDistinct)
        XCTAssertEqual(identity.displayName, "the Chat conversation")
    }

    func testCoworkTaskIsIdentifiedByTitleOnly() throws {
        let identity = try identity("claude-cowork-conversation", selectors: claude)
        XCTAssertNil(identity.route, "Cowork stays on /new")
        XCTAssertEqual(identity.title, "Untangling the fixture suite")
        XCTAssertTrue(identity.isDistinct)
        XCTAssertEqual(identity.surface, "Cowork")
    }

    func testProjectURLIsNotAConversationIdentity() throws {
        let identity = try identity("claude-project-chat", selectors: claude)
        XCTAssertNil(identity.route, "a project holds many conversations")
        XCTAssertEqual(identity.title, "Errol project")
        XCTAssertTrue(identity.isDistinct, "the window's title still names it")
    }

    func testChatGPTConversationIsIdentifiedByTitleAndHomeByNothing() throws {
        let conversation = try identity("chatgpt-chat-conversation", selectors: chatgpt)
        XCTAssertNil(conversation.route, "the desktop app exposes no conversation URL")
        XCTAssertEqual(conversation.title, "Logo brainstorm")
        XCTAssertTrue(conversation.isDistinct)
        let home = try identity("chatgpt-chat-home", selectors: chatgpt)
        XCTAssertNil(home.route, "the app:// shell URL is not the app's web host")
        XCTAssertTrue(home.titleIsGeneric)
        XCTAssertFalse(home.isDistinct)
        XCTAssertEqual(home.surface, "Chat")
    }

    // MARK: Comparison

    private func compare(_ bound: DestinationIdentity, _ now: DestinationIdentity,
                         adoptionOpen: Bool = false, selectors: AppSelectors? = nil) -> DestinationVerdict {
        compareDestination(bound: bound, now: now, adoptionOpen: adoptionOpen, selectors: selectors ?? claude)
    }

    func testTheSameRouteIsTheSameConversationWhateverTheTitleDoes() throws {
        let bound = try identity("claude-chat-conversation", selectors: claude)
        var renamed = bound
        renamed.title = "A better name"
        XCTAssertEqual(compare(bound, renamed), .same)
        // The multiwindow fixture's chat window shows the same route.
        let other = try identity("claude-multiwindow", window: 0, selectors: claude)
        XCTAssertEqual(compare(bound, other), .same)
    }

    func testAnotherRouteIsAnotherConversation() throws {
        let bound = try identity("claude-chat-conversation", selectors: claude)
        let other = try identity("claude-sidebar-stop-trap", selectors: claude)
        XCTAssertEqual(compare(bound, other, adoptionOpen: true),
                       .changed("showing \u{201C}Stop procrastinating plan\u{201D}"),
                       "a bound route is binding even while adoption is open")
    }

    func testLeavingABoundRouteForANewChatIsAChange() throws {
        let bound = try identity("claude-chat-conversation", selectors: claude)
        let fresh = try identity("claude-chat-home", selectors: claude)
        XCTAssertEqual(compare(bound, fresh), .changed("showing a new chat"))
    }

    func testAFreshChatAdoptsItsRouteOnlyWhileAdoptionIsOpen() throws {
        let fresh = try identity("claude-chat-home", selectors: claude)
        let named = try identity("claude-chat-conversation", selectors: claude)
        XCTAssertEqual(compare(fresh, named, adoptionOpen: true), .adopted(named),
                       "the opener gave the chat its route: that is the conversation now")
        XCTAssertEqual(compare(fresh, named, adoptionOpen: false),
                       .changed("showing \u{201C}Errol brand naming\u{201D}"),
                       "after the first reply, a route appearing is navigation")
    }

    func testAnUnnamedChatBeingNamedIsAdoptedAtAnyTime() {
        let bound = DestinationIdentity(title: "ChatGPT", titleIsGeneric: true, surface: "Chat")
        let named = DestinationIdentity(title: "Logo brainstorm", titleIsGeneric: false, surface: "Chat")
        XCTAssertEqual(compare(bound, named, adoptionOpen: false, selectors: chatgpt), .adopted(named),
                       "automatic naming lags the first exchange by an unpredictable while")
        XCTAssertEqual(compare(bound, bound, selectors: chatgpt), .same,
                       "two unnamed chats cannot be told apart, and the binding said so")
    }

    func testANamedConversationWithoutARouteHoldsByTitle() {
        let bound = DestinationIdentity(title: "Logo brainstorm", titleIsGeneric: false, surface: "Chat")
        let other = DestinationIdentity(title: "Quarterly report", titleIsGeneric: false, surface: "Chat")
        let fresh = DestinationIdentity(title: "ChatGPT", titleIsGeneric: true, surface: "Chat")
        XCTAssertEqual(compare(bound, bound, selectors: chatgpt), .same)
        XCTAssertEqual(compare(bound, other, selectors: chatgpt),
                       .changed("showing \u{201C}Quarterly report\u{201D}"))
        XCTAssertEqual(compare(bound, fresh, selectors: chatgpt), .changed("showing a new chat"))
    }

    func testSwitchingWorldsOrSurfacesIsAChange() throws {
        let chat = try identity("claude-chat-home", selectors: claude)
        let code = try identity("claude-code-collapsed", selectors: claude)
        XCTAssertEqual(compare(chat, code, adoptionOpen: true), .changed("now showing a Code session"),
                       "the Code world replacing the chat in the one window is not adoption")
        XCTAssertEqual(compare(code, chat), .changed("no longer showing the Code session"))
        let cowork = try identity("claude-cowork-home", selectors: claude)
        XCTAssertEqual(compare(chat, cowork), .changed("switched to Cowork"))
    }

    func testTheNewChatSurfaceNameIsNotComparedAgainstTheTabName() {
        // A fresh chat reads "Chat" from its tab pair and "New chat" from
        // its /new URL once the tabs unmount; neither is a switch.
        let tab = DestinationIdentity(title: "Claude", titleIsGeneric: true, surface: "Chat")
        let path = DestinationIdentity(title: "Claude", titleIsGeneric: true, surface: "New chat")
        XCTAssertEqual(compare(tab, path), .same)
        XCTAssertEqual(compare(path, tab), .same)
    }

    // MARK: Block wording

    func testBlockLinesNameTheSideAndWhatClearsThem() {
        let names = (chatgpt: "ChatGPT", claude: "Claude")
        let changed = RunBlock.destinationChanged(side: .claude, bound: "\u{201C}Onboarding ideas\u{201D}",
                                                  seen: "showing \u{201C}Quarterly report\u{201D}")
        XCTAssertEqual(changed.headline(names: names), "Paused: Claude's conversation changed")
        XCTAssertTrue(changed.recovery(names: names).contains("Return to \u{201C}Onboarding ideas\u{201D} to continue, or Stop"))
        XCTAssertTrue(changed.logLine(name: "Claude").hasPrefix("Paused — Claude's conversation changed"))
        let draft = RunBlock.draft(side: .chatgpt, characters: 16)
        XCTAssertEqual(draft.headline(names: names), "Paused: ChatGPT has an unsent draft")
        XCTAssertTrue(draft.recovery(names: names).contains("16-character draft"))
        XCTAssertEqual(draft.startRefusal(name: "ChatGPT"),
                       "ChatGPT has an unsent draft (16 characters). Finish or clear it, then send again.")
        XCTAssertEqual(RunBlock.historyChanged(side: .claude).headline(names: names),
                       "Paused: Claude's conversation moved on")
    }
}

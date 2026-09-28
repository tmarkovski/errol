// What identifies a conversation on each surface, read from the recorded
// fixtures: the name the destination goes by in the window chooser and in
// the log. The fixture facts are the ones the first-run proposal tabulated
// (docs/design-proposals/first-run-usability): /chat/<uuid> and
// /epitaxy/<id> name a conversation, /new and /project/<uuid> do not, and
// ChatGPT exposes no conversation URL at all. Nothing here compares one
// reading against a later one: the binding is to the window, and what it
// shows afterwards is not judged (Core/Setup/Destination.swift).

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
        // it from any other unnamed chat; the details call it a new chat.
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

    // MARK: Block wording

    func testBlockLinesNameTheSideAndWhatClearsThem() {
        let names = SideNames(chatgpt: "ChatGPT", claude: "Claude")
        let hidden = RunBlock.windowHidden(side: .claude, seen: "minimized")
        XCTAssertEqual(hidden.headline(names: names), "Paused: Claude's window isn't showing")
        XCTAssertTrue(hidden.recovery(names: names).contains("It is minimized. Bring it back to continue, or Stop"))
        XCTAssertTrue(hidden.logLine(name: "Claude").hasPrefix("Paused — Claude's window is minimized"))
        XCTAssertEqual(hidden.startRefusal(name: "Claude"), "Claude's window is minimized. Bring it back, then send again.")
        let draft = RunBlock.draft(side: .chatgpt, characters: 16)
        XCTAssertEqual(draft.headline(names: names), "Paused: ChatGPT has an unsent draft")
        XCTAssertTrue(draft.recovery(names: names).contains("16-character draft"))
        XCTAssertEqual(draft.startRefusal(name: "ChatGPT"),
                       "ChatGPT has an unsent draft (16 characters). Finish or clear it, then send again.")
        XCTAssertEqual(RunBlock.historyChanged(side: .claude).headline(names: names),
                       "Paused: Claude's conversation moved on")
        let front = RunBlock.notInFront(side: .chatgpt)
        XCTAssertEqual(front.headline(names: names), "Paused: ChatGPT couldn't be brought to the front")
        XCTAssertTrue(front.recovery(names: names).hasPrefix("Click ChatGPT's window to bring it to the front"))
        XCTAssertTrue(front.logLine(name: "ChatGPT").hasPrefix("Paused — ChatGPT would not come to the front"))
        XCTAssertEqual(front.startRefusal(name: "ChatGPT"),
                       "ChatGPT couldn't be brought to the front. Click its window, then send again.")
    }
}

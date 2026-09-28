// ChatGPT fixture scenarios: every surface and screen the detection has to
// classify — Chat and Work, home screen (new chat) and open conversation
// (plugging into an existing chat), Codex mode, and mid-stream. The trees are
// synthesized from the live-verified shapes in docs/how-it-works.md's field notes
// (Aug 2026); recapture with `tools/ax-dump.swift chatgpt --capture` when an
// app update moves them. ERROL_TEST_LOG=1 dumps each tree and what detection
// concluded.

import XCTest
@testable import ErrolKit

final class ChatGPTScenarioTests: XCTestCase {
    let selectors = config.chatgptSelectors

    func detectChatGPT(_ fixture: String, file: StaticString = #filePath,
                       line: UInt = #line) -> Detection {
        detect(fixture: fixture, selectors: selectors, appName: "ChatGPT",
               file: file, line: line)
    }

    // MARK: New chats (home screens)

    func testChatHomeIsReadyWithZeroAffordances() {
        // Real capture (Aug 27 2026), sidebar titles anonymized: the one
        // fixture in this file recorded from a live tree rather than
        // synthesized. The synthesized expectations held against it
        // unchanged — including no send control over the empty composer.
        let d = detectChatGPT("chatgpt-chat-home")
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.headline, "Ready")
        // The toggle pair (mounted only on home screens) names the surface;
        // the mode popup says "ChatGPT" for both Chat and Work and must not win.
        XCTAssertEqual(d.status.surface, "Chat")
        // Default model: the pill's title is empty and only the description
        // ("Select ChatGPT model") remains — reported as "Default".
        XCTAssertEqual(d.status.model, "Default")
        XCTAssertEqual(d.excluded, [false])
        // An empty chat exposes no copy buttons. That is the home screen
        // itself, not selector breakage — the baseline a run seeded here
        // starts counting affordances up from.
        XCTAssertTrue(d.affordanceLabels.isEmpty)
        XCTAssertTrue(d.copyLabels.isEmpty)
        XCTAssertFalse(d.streaming)
        // ChatGPT unmounts the send control while the composer is empty.
        XCTAssertNil(d.sendLabel)
        XCTAssertEqual(d.composerLabel, "Message ChatGPT")
    }

    func testWorkHomeNamesSurfaceAndModel() {
        let d = detectChatGPT("chatgpt-work-home")
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Work")
        // On Work the pill always carries the exact model and effort as its title.
        XCTAssertEqual(d.status.model, "5.6 Sol High")
        XCTAssertTrue(d.affordanceLabels.isEmpty)
    }

    // MARK: Existing conversations (plugging into an open chat)

    func testChatConversationCountsOnlyResponses() {
        let d = detectChatGPT("chatgpt-chat-conversation")
        XCTAssertEqual(d.status.state, .ready)
        // Conversations unmount the toggle pair; the per-surface composer
        // placeholder is the remaining marker.
        XCTAssertEqual(d.status.surface, "Chat")
        XCTAssertEqual(d.status.model, "5.6 Sol Medium")
        XCTAssertEqual(d.status.detail, "\u{201C}Logo brainstorm\u{201D}")
        // Two exchanges: the user echoes ("Copy message") and the qualified
        // copies ("Copy code", "Copy table") stay out of the count — only the
        // two responses register. This baseline is what waitForResponse
        // measures against when the relay joins an existing chat.
        XCTAssertEqual(d.affordanceLabels, ["Copy", "Copy newest"])
        XCTAssertEqual(d.copyLabels, ["Copy", "Copy newest"])
        // Depth-first order: the last copy button belongs to the newest
        // response — the one copyLastResponse presses.
        XCTAssertTrue(d.copyLabels.last?.contains("newest") == true)
        XCTAssertEqual(d.sendLabel, "Send")
        XCTAssertFalse(d.streaming)
        XCTAssertFalse(d.lastAffordanceIsToggle)
    }

    func testWorkConversationKeepsPlaceholderSurface() {
        // Expected shape, not yet observed live (docs/how-it-works.md): a Work conversation
        // keeps the "Work with ChatGPT" placeholder after the toggles unmount.
        let d = detectChatGPT("chatgpt-work-conversation")
        XCTAssertEqual(d.status.surface, "Work")
        XCTAssertEqual(d.status.model, "5.6 Sol High")
        XCTAssertEqual(d.affordanceLabels, ["Copy newest"])
    }

    func testCodexConversationFallsBackToModePopup() {
        let d = detectChatGPT("chatgpt-codex-conversation")
        // No toggles, no placeholder: the mode switcher still distinguishes
        // Codex, the one mode it reports faithfully.
        XCTAssertEqual(d.status.surface, "Codex")
        XCTAssertEqual(d.status.model, "Default")
        XCTAssertEqual(d.affordanceLabels, ["Copy newest"])
    }

    // MARK: Streaming

    func testStreamingShowsStopAndNoNewAffordance() {
        let d = detectChatGPT("chatgpt-chat-streaming")
        XCTAssertTrue(d.streaming)
        // The just-sent echo mounts only "Copy message", which the selector
        // excludes: on ChatGPT the count moves on responses alone. This is
        // the tree-level face of the Codex fast-reply race — with
        // echoCountsAsAffordance false, nothing here may register.
        XCTAssertTrue(d.affordanceLabels.isEmpty)
    }

    // MARK: Terminal panel

    func testTerminalInputIsNotTheComposer() throws {
        // With the terminal panel open, ChatGPT mounts its input as a text
        // field below the composer in the tree (live Sep 24 2026). Taken
        // for the composer, it got the relayed message, and the Return
        // that sent it ran the message in the shell. The composer holds a
        // draft here, so the terminal's empty value must not stand in for it.
        var window = try XCTUnwrap(loadFixture("chatgpt-chat-conversation").first)
        window.children.append(FixtureElement(role: "AXTextField", axDescription: "Terminal input",
                                              title: "Terminal input", value: .string("")))
        let composer = try XCTUnwrap(composerElement(under: window))
        XCTAssertEqual(composer.role, "AXTextArea")
        XCTAssertEqual(composer.label, "Message ChatGPT")
        let scan = scanWindow(window, selectors: selectors)
        XCTAssertEqual(scan.composerLabel, "Message ChatGPT")
        XCTAssertEqual(classifyComposer(value: scan.composerValue, label: scan.composerLabel,
                                        attachments: 0, replying: false),
                       .draft(characters: 16))
    }

    // MARK: File pane

    func testFilePaneEditorIsNotTheComposer() throws {
        // With a file open in the side pane, ChatGPT mounts the file's
        // editor (CodeMirror: editable, unnamed) as a text area after the
        // composer in the tree, inside the pane's complementary landmark
        // (live Sep 28 2026). Taken for the composer, the file's text read
        // as an unsent draft whenever ChatGPT was not in front, and a run
        // was held on it.
        let d = detectChatGPT("chatgpt-file-pane")
        XCTAssertEqual(d.composerLabel, "Do anything Do anything")
        let scan = try XCTUnwrap(d.scans.first)
        XCTAssertTrue(scan.hasComposer)
        XCTAssertEqual(scan.composerLabel, "Do anything Do anything")
        XCTAssertEqual(classifyComposer(value: scan.composerValue, label: scan.composerLabel,
                                        attachments: 0, replying: false), .empty)
    }

    func testFilePaneCopyIsNotTheReplysCopy() throws {
        // The pane's "Copy Markdown" matches the copy rule and is the last
        // match in the tree. Pressed as the reply's copy, it took the open
        // file as ChatGPT's reply. It still counts among the copy buttons
        // (the count is a baseline taken with the pane as it stands); it is
        // never the one pressed.
        let d = detectChatGPT("chatgpt-file-pane")
        XCTAssertEqual(d.copyLabels, ["Copy Copy newest", "Copy Markdown Copy Markdown"])
        let window = try XCTUnwrap(d.windows.first)
        XCTAssertEqual(replyCopyButton(under: window, selectors: selectors)?.label, "Copy Copy newest")
        XCTAssertEqual(newestMessageAffordance(under: window, selectors: selectors)?.label, "Copy Copy newest")
    }

    func testWindowsWithoutSidePanelsPressTheLastCopy() {
        // The side-panel rule changes nothing where there is no panel.
        for fixture in ["chatgpt-chat-conversation", "chatgpt-work-conversation", "chatgpt-codex-conversation"] {
            let d = detectChatGPT(fixture)
            guard let window = d.chosenIndex.map({ d.windows[$0] }) else {
                XCTFail("\(fixture): no chat window"); continue
            }
            XCTAssertEqual(replyCopyButton(under: window, selectors: selectors)?.label,
                           d.copyLabels.last, fixture)
        }
    }

    // MARK: Sidebar titles

    func testSidebarTitleContainingCopyIsNotACopyButton() throws {
        // A conversation titled "Copy editing tips" meets the copy rule by its
        // label, and it once registered as a message affordance: one real
        // response plus one poisoned title made 2. Its row is not a command,
        // though: ChatGPT names it after the title and draws the title inside
        // it, beside its Pin and Archive buttons (live Sep 28 2026), where the
        // response's Copy is an icon the app names "Copy" (isAppCommand).
        let d = detectChatGPT("chatgpt-sidebar-copy-trap")
        XCTAssertEqual(d.copyLabels, ["Copy newest"])
        XCTAssertEqual(d.affordanceLabels, ["Copy newest"])
        let window = try XCTUnwrap(d.windows.first)
        let row = try XCTUnwrap(firstMatch(in: window) {
            $0.role == kAXButtonRole as String && $0.title == "Copy editing tips"
        })
        XCTAssertTrue(isCopyButtonLabel(row.label, selectors: selectors),
                      "the label alone still meets the rule; the row's shape is what rules it out")
        XCTAssertFalse(isCopyButton(row, selectors: selectors))
    }
}

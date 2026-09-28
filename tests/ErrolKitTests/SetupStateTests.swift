// The console's setup state, driven the way the engine's observations and
// the human's actions drive it in the app: presence from sweeps, a side
// connected on its own only where that takes no guess, connections judged
// by the same evidence the run's preflight uses, and a side losing its
// conversation reopening only that side.

import XCTest
@testable import ErrolKit

final class SetupStateTests: XCTestCase {
    private let names = SideNames(chatgpt: "ChatGPT", claude: "Claude")
    private let chatgpt = config.chatgptSelectors
    private let claude = config.claudeSelectors

    private func candidate(_ fixture: String, window index: Int = 0, id: UInt = 1,
                           selectors: AppSelectors) throws -> WindowCandidate {
        let windows = loadFixture(fixture)
        let window = try XCTUnwrap(windows.indices.contains(index) ? windows[index] : nil)
        return WindowCandidate(id: WindowID(raw: id), scan: scanWindow(window, selectors: selectors),
                               selectors: selectors)
    }

    private func observation(_ candidate: WindowCandidate,
                             check: BoundDestination.Check = .same) -> BindingObservation {
        BindingObservation(window: candidate.id, check: check, identity: candidate.identity,
                           composer: candidate.composer)
    }

    /// A state with both apps running and one ready window each.
    private func prepared() throws -> (SetupState, WindowCandidate, WindowCandidate) {
        var state = SetupState()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let cld = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .available(windows: 1), candidates: [cld])
        return (state, gpt, cld)
    }

    /// Both sides connected.
    private func composed() throws -> SetupState {
        var (state, gpt, cld) = try prepared()
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))
        return state
    }

    // MARK: The apps

    func testStartsCheckingAndAsksForTheApps() {
        var state = SetupState()
        XCTAssertEqual(state.notice(names: names), SetupNotice(text: "Checking ChatGPT\u{2026}", isProblem: false))
        state.observe(.chatgpt, presence: .notRunning, candidates: [])
        state.observe(.claude, presence: .notRunning, candidates: [])
        XCTAssertEqual(state.notice(names: names)?.text, "Open ChatGPT and Claude to begin.")
        XCTAssertEqual(state.sendBlocker(names: names), "Open ChatGPT and Claude to begin.")
        state.observe(.chatgpt, presence: .noConversation, candidates: [])
        XCTAssertEqual(state.notice(names: names)?.text, "Open Claude to begin.")
        state.observe(.claude, presence: .notInstalled, candidates: [])
        XCTAssertEqual(state.notice(names: names)?.isProblem, true, "a missing app is the human's to fix")
    }

    func testPresenceFollowsTheSweepAndNamesTheNextAction() throws {
        XCTAssertEqual(appPresence(installed: false, status: SideStatus(appName: "ChatGPT", state: .missing),
                                   candidates: []), .notInstalled)
        XCTAssertEqual(appPresence(installed: true, status: SideStatus(appName: "ChatGPT", state: .missing),
                                   candidates: []), .notRunning)
        XCTAssertEqual(appPresence(installed: true, status: SideStatus(appName: "ChatGPT", state: .notReady),
                                   candidates: []), .noWindow)
        let home = try candidate("chatgpt-chat-home", selectors: chatgpt)
        XCTAssertEqual(appPresence(installed: true, status: SideStatus(appName: "ChatGPT", state: .ready),
                                   candidates: [home]), .available(windows: 1))
        XCTAssertEqual(AppPresence.notRunning.action(name: "ChatGPT"), "Open ChatGPT")
        XCTAssertEqual(AppPresence.launching.action(name: "ChatGPT"), "Opening\u{2026}")
        XCTAssertEqual(AppPresence.noConversation.action(name: "Claude"), "Open a conversation")
        XCTAssertEqual(AppPresence.available(windows: 2).action(name: "Claude"), "Ready")
    }

    func testALaunchStaysOpeningUntilTheAppIsSeen() throws {
        var state = SetupState()
        state.observe(.chatgpt, presence: .notRunning, candidates: [])
        state.launching(.chatgpt)
        state.observe(.chatgpt, presence: .notRunning, candidates: [])
        XCTAssertEqual(state.chatgpt.presence, .launching, "a sweep from before the app came up says nothing")
        XCTAssertEqual(state.notice(names: names)?.text, "Opening ChatGPT\u{2026}")
        state.observe(.chatgpt, presence: .noWindow, candidates: [])
        XCTAssertEqual(state.chatgpt.presence, .noWindow)
        state.launching(.claude)
        state.launchFailed(.claude, installed: false)
        XCTAssertEqual(state.claude.presence, .notInstalled)
    }

    // MARK: Arrange

    func testTheLayoutAppliesAsChosen() throws {
        var (state, _, _) = try prepared()
        XCTAssertEqual(state.layout, .keepPositions, "the windows stay where they are unless a layout is chosen")
        XCTAssertTrue(state.layoutApplied, "keep positions applies itself")
        XCTAssertTrue(state.canArrange, "one eligible window each is the window to move")
        state.choose(.sideBySide)
        XCTAssertFalse(state.layoutApplied, "a moving layout waits for the engine's word")
        state.layoutOutcome(.cannotFit(.chatgpt, "ChatGPT's window can't be made 640\u{00D7}900 on this display."))
        XCTAssertFalse(state.layoutApplied)
        XCTAssertTrue(state.layoutProblem!.hasSuffix("Both windows stay where they were."))
        state.layoutOutcome(.arranged)
        XCTAssertTrue(state.layoutApplied)
        XCTAssertNil(state.layoutProblem)
        state.choose(.keepPositions)
        XCTAssertTrue(state.layoutApplied)
    }

    func testAMissingWindowLeavesTheLayoutToApplyLater() throws {
        var (state, _, _) = try prepared()
        state.choose(.stacked)
        state.layoutOutcome(.windowMissing(.claude))
        XCTAssertFalse(state.layoutApplied)
        XCTAssertNil(state.layoutProblem, "the sweep says what to open; the layout applies again once it is there")
    }

    func testSeveralWindowsGiveNothingToMoveUntilOneIsConnected() throws {
        var state = SetupState()
        let one = try candidate("claude-chat-conversation", id: 1, selectors: claude)
        let two = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, presence: .available(windows: 2), candidates: [one, two])
        XCTAssertNil(state.claude.arrangementTarget)
        XCTAssertTrue(state.claude.needsWindowChoice)
        XCTAssertFalse(state.canArrange)
        // The connection names the window to move.
        state.connected(.claude, window: one.id, identity: one.identity, model: nil, observation: observation(one))
        XCTAssertEqual(state.claude.arrangementTarget, one.id)
        XCTAssertFalse(state.claude.needsWindowChoice)
        XCTAssertTrue(state.claude.hasSeveralWindows, "the chooser stays, to switch windows")
    }

    func testTheChooserNamesWindowsByTitleAndNumbersTheUntitled() throws {
        var side = SideSetup(side: .chatgpt)
        let named = try candidate("chatgpt-chat-conversation", id: 1, selectors: chatgpt)
        var scan = WindowScan()
        scan.title = "ChatGPT"
        scan.hasComposer = true
        let first = WindowCandidate(id: WindowID(raw: 2), scan: scan, selectors: chatgpt)
        let second = WindowCandidate(id: WindowID(raw: 3), scan: scan, selectors: chatgpt)
        side.candidates = [named, first]
        XCTAssertEqual(side.windowChoices.map(\.label), ["\u{201C}Logo brainstorm\u{201D}", "Untitled window"])
        side.candidates = [first, named, second]
        XCTAssertEqual(side.windowChoices.map(\.label),
                       ["Untitled window 1", "\u{201C}Logo brainstorm\u{201D}", "Untitled window 2"])
        XCTAssertEqual(side.windowChoices.map(\.id), [first.id, named.id, second.id], "the app's order holds")
    }

    // MARK: Connect

    func testOnlyASideWithOneUsableWindowIsConnectedForIt() throws {
        var state = SetupState()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let named = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        let fresh = try candidate("claude-chat-home", id: 3, selectors: claude)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .available(windows: 2), candidates: [named, fresh])

        XCTAssertEqual(state.automaticConnection(for: .chatgpt), gpt.id)
        XCTAssertNil(state.automaticConnection(for: .claude), "several windows are never chosen among")
        XCTAssertTrue(state.claude.needsWindowChoice)
        XCTAssertEqual(state.notice(names: names)?.text, "Connecting ChatGPT\u{2026}")

        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertNil(state.automaticConnection(for: .chatgpt), "a connected side is left alone")
        XCTAssertEqual(state.notice(names: names)?.text,
                       "Claude has 2 windows open. Click the line below to choose one.")

        state.connected(.claude, window: named.id, identity: named.identity, model: nil,
                        observation: observation(named))
        XCTAssertNil(state.notice(names: names))
        XCTAssertNil(state.sendBlocker(names: names))
    }

    func testConnectingBothSidesReadsReady() throws {
        let state = try composed()
        XCTAssertTrue(state.chatgpt.isReady)
        XCTAssertTrue(state.claude.isReady)
        XCTAssertNil(state.sendBlocker(names: names))
    }

    func testAWorkSurfaceConnectsLikeAnyConversation() throws {
        // An existing Code session is a place the human chose on purpose: it
        // is named as one in the window chooser and asks for no further choice.
        var state = SetupState()
        let code = try candidate("claude-code-collapsed", selectors: claude)
        XCTAssertTrue(code.isEligible, "Claude allows a Code session when the human picks it")
        XCTAssertEqual(code.name, "Code session")
        state.connected(.claude, window: code.id, identity: code.identity, model: nil, observation: observation(code))
        XCTAssertEqual(state.claude.connection?.readiness, .ready)
        XCTAssertNil(state.claude.connection?.readiness.problem(name: "Claude"))
        state.observe(.claude, binding: observation(code))
        XCTAssertEqual(state.claude.connection?.readiness, .ready)
    }

    func testTheConnectedWindowIsReadFromTheLatestSweep() throws {
        // The connection keeps the model it was made with; what the window
        // shows now comes from the sweep's candidate for that same window,
        // and from no other window.
        var (state, gpt, _) = try prepared()
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: "5.6 Sol High",
                        observation: observation(gpt))
        XCTAssertEqual(state.chatgpt.connectedCandidate?.id, gpt.id)

        var scan = scanWindow(try XCTUnwrap(loadFixture("chatgpt-chat-home").first), selectors: chatgpt)
        scan.model = "5.6 Sol Low"
        let switched = WindowCandidate(id: gpt.id, scan: scan, selectors: chatgpt)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [switched])
        XCTAssertEqual(state.chatgpt.connectedCandidate?.model, "5.6 Sol Low")
        XCTAssertEqual(state.chatgpt.connection?.model, "5.6 Sol High")

        let other = WindowCandidate(id: WindowID(raw: 9), scan: scan, selectors: chatgpt)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [other])
        XCTAssertNil(state.chatgpt.connectedCandidate, "another window's reading is not this one's")
        XCTAssertNil(state.claude.connectedCandidate, "nothing is read for a side that is not connected")
    }

    func testADraftIsAFinishPreparingStepNotAConnectionLoss() throws {
        var state = try composed()
        let drafted = try candidate("chatgpt-chat-conversation", id: 1, selectors: chatgpt)
        XCTAssertEqual(drafted.composer, .draft(characters: 16))
        state.observe(.chatgpt, binding: observation(drafted))
        XCTAssertTrue(state.chatgpt.isConnected, "the connection stands; the draft is the human's to finish")
        XCTAssertEqual(state.chatgpt.connection?.readiness, .finishPreparing(.draft(side: .chatgpt, characters: 16)))
        XCTAssertEqual(state.sendBlocker(names: names),
                       "ChatGPT has an unsent draft (16 characters). Finish or clear it, then send again.")
        XCTAssertEqual(state.notice(names: names)?.isProblem, true)
        let home = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        state.observe(.chatgpt, binding: observation(home))
        XCTAssertNil(state.sendBlocker(names: names))
    }

    func testAHiddenWindowBlocksSendingAndKeepsTheOtherSide() throws {
        var state = try composed()
        let claudeHome = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, binding: observation(claudeHome, check: .hidden("minimized")))
        XCTAssertTrue(state.claude.isConnected, "the connection stands; the window is the human's to bring back")
        XCTAssertEqual(state.claude.connection?.readiness, .hidden("minimized"))
        XCTAssertEqual(state.sendBlocker(names: names), "Claude's window is minimized. Bring it back to send.")
        XCTAssertTrue(state.chatgpt.isReady, "the other side is untouched")
    }

    func testAStaleBindingObservationLeavesANewerConnectionAlone() throws {
        // A sweep reads the binding on its own thread, so its word on the
        // window the side was connected to can land after the human has
        // switched it to another. It says nothing of the newer window: it
        // neither relabels it nor, lost, disconnects it.
        var state = SetupState()
        let older = try candidate("claude-chat-home", id: 1, selectors: claude)
        let newer = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        XCTAssertNotEqual(older.identity, newer.identity)
        state.observe(.claude, presence: .available(windows: 2), candidates: [older, newer])
        state.connected(.claude, window: newer.id, identity: newer.identity, model: nil,
                        observation: observation(newer))
        state.observe(.claude, binding: observation(older, check: .lost("the window closed")))
        XCTAssertEqual(state.claude.connection?.window, newer.id, "the newer connection stands")
        XCTAssertEqual(state.claude.connection?.identity, newer.identity)
        XCTAssertEqual(state.claude.connection?.readiness, .ready)
    }

    func testALostConversationReopensOnlyThatSide() throws {
        var state = try composed()
        state.observe(.claude, binding: observation(state.claude.connectedCandidate!, check: .lost("the window closed")))
        XCTAssertNil(state.claude.connection)
        XCTAssertNotNil(state.chatgpt.connection, "the other side keeps its conversation")
        XCTAssertEqual(state.automaticConnection(for: .claude), state.claude.eligible[0].id,
                       "the side's one window is connected again as the next sweep sees it")
    }

    func testDisconnectingASideKeepsTheOther() throws {
        var state = try composed()
        state.disconnect(.chatgpt)
        XCTAssertNil(state.chatgpt.connection)
        XCTAssertTrue(state.claude.isConnected)
        XCTAssertEqual(state.notice(names: names)?.text, "Connecting ChatGPT\u{2026}")
    }

    // MARK: Return

    func testReturningMarksBothConnectionsUnverifiedUntilObserved() throws {
        var state = try composed()
        state.markUnverified()
        XCTAssertEqual(state.chatgpt.connection?.readiness, .unverified)
        XCTAssertFalse(state.chatgpt.isReady)
        XCTAssertEqual(state.chatgpt.connection?.readiness.shortStatus, "Last used")
        XCTAssertEqual(state.sendBlocker(names: names), "Checking ChatGPT's conversation\u{2026}")
        XCTAssertEqual(state.notice(names: names)?.isProblem, false, "a wait is not a problem")
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let cld = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        state.observe(.chatgpt, binding: observation(gpt))
        state.observe(.claude, binding: observation(cld))
        XCTAssertNil(state.sendBlocker(names: names))
    }

    func testChangingTheLayoutLaterAppliesOnItsOwn() throws {
        var state = try composed()
        state.choose(.stacked)
        XCTAssertEqual(state.layout, .stacked)
        XCTAssertFalse(state.layoutApplied, "a moving layout waits for the engine's word")
        XCTAssertTrue(state.canArrange, "the connected windows are the ones to move")
    }
}

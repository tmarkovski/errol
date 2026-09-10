// The setup flow's state machine, driven the way the engine's observations
// and the human's actions drive it in the app: presence from sweeps, the
// steps completing only on their actions, connections judged by the same
// evidence the run's preflight uses, and a side losing its conversation
// reopening only that side.

import XCTest
@testable import ErrolKit

final class SetupStateTests: XCTestCase {
    private let names = (chatgpt: "ChatGPT", claude: "Claude")
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
        BindingObservation(check: check, identity: candidate.identity, composer: candidate.composer)
    }

    /// A state with both apps running and one ready window each, at the
    /// prepare step.
    private func prepared() throws -> (SetupState, WindowCandidate, WindowCandidate) {
        var state = SetupState()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let cld = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .available(windows: 1), candidates: [cld])
        return (state, gpt, cld)
    }

    /// The whole guided flow through to the editor.
    private func composed() throws -> SetupState {
        var (state, gpt, cld) = try prepared()
        XCTAssertTrue(state.continueFromPrepare())
        state.choose(.keepPositions)
        state.layoutOutcome(.kept, names: names)
        XCTAssertTrue(state.continueFromArrange())
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))
        return state
    }

    // MARK: Prepare

    func testStartsAtPrepareWithNothingDone() {
        var state = SetupState()
        XCTAssertEqual(state.phase, .prepareApps)
        XCTAssertEqual(state.progress(of: .prepareApps), .current)
        XCTAssertEqual(state.progress(of: .arrange), .remaining)
        XCTAssertEqual(state.progressDescription(names: names), "Step 1 of 4: Open the apps")
        XCTAssertFalse(state.continueFromPrepare(), "nothing is known about the apps yet")
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
        XCTAssertNil(AppPresence.available(windows: 1).problem(name: "Claude"))
        XCTAssertTrue(AppPresence.notInstalled.problem(name: "ChatGPT")!.contains("isn't installed"))
    }

    func testALaunchStaysOpeningUntilTheAppIsSeen() throws {
        var state = SetupState()
        state.observe(.chatgpt, presence: .notRunning, candidates: [])
        state.launching(.chatgpt)
        state.observe(.chatgpt, presence: .notRunning, candidates: [])
        XCTAssertEqual(state.chatgpt.presence, .launching, "a sweep from before the app came up says nothing")
        state.observe(.chatgpt, presence: .noWindow, candidates: [])
        XCTAssertEqual(state.chatgpt.presence, .noWindow)
        state.launching(.claude)
        state.launchFailed(.claude, installed: false)
        XCTAssertEqual(state.claude.presence, .notInstalled)
    }

    func testContinueNeedsBothAppsAvailableAndCompletesTheStep() throws {
        var state = SetupState()
        let gpt = try candidate("chatgpt-chat-home", selectors: chatgpt)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .noConversation, candidates: [])
        XCTAssertFalse(state.continueFromPrepare())
        XCTAssertEqual(state.phase, .prepareApps)
        let cld = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, presence: .available(windows: 1), candidates: [cld])
        XCTAssertTrue(state.continueFromPrepare())
        XCTAssertEqual(state.phase, .arrange)
        XCTAssertEqual(state.progress(of: .prepareApps), .done)
        XCTAssertEqual(state.progress(of: .arrange), .current)
    }

    // MARK: Arrange

    func testArrangementCompletesOnlyWhenAppliedOrDeliberatelyKept() throws {
        var (state, _, _) = try prepared()
        state.continueFromPrepare()
        XCTAssertTrue(state.canArrange, "one eligible window each is the window to move")
        XCTAssertFalse(state.continueFromArrange(), "nothing applied yet")
        state.layoutOutcome(.cannotFit(.chatgpt, "ChatGPT's window can't be made 640\u{00D7}900 on this display."),
                            names: names)
        XCTAssertFalse(state.layoutApplied)
        XCTAssertTrue(state.layoutProblem!.contains("Keep positions"))
        XCTAssertEqual(state.progress(of: .arrange), .current)
        state.layoutOutcome(.arranged, names: names)
        XCTAssertTrue(state.layoutApplied)
        XCTAssertNil(state.layoutProblem)
        XCTAssertEqual(state.progress(of: .arrange), .done)
        state.choose(.stacked)
        XCTAssertFalse(state.layoutApplied, "another layout must be applied in its turn")
        XCTAssertEqual(state.progress(of: .arrange), .current)
        state.choose(.keepPositions)
        state.layoutOutcome(.kept, names: names)
        XCTAssertTrue(state.continueFromArrange())
        XCTAssertEqual(state.phase, .connect(.chatgpt), "ChatGPT connects first, whoever starts")
    }

    func testSeveralWindowsNeedAnExplicitOneBeforeArranging() throws {
        var state = SetupState()
        let one = try candidate("claude-chat-conversation", id: 1, selectors: claude)
        let two = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, presence: .available(windows: 2), candidates: [one, two])
        XCTAssertNil(state.claude.arrangementTarget)
        XCTAssertTrue(state.claude.needsArrangementChoice)
        state.chooseArrangementWindow(.claude, two.id)
        XCTAssertEqual(state.claude.arrangementTarget, two.id)
        XCTAssertFalse(state.claude.needsArrangementChoice)
        // A connection outranks the choice.
        state.connected(.claude, window: one.id, identity: one.identity, model: nil, observation: observation(one))
        XCTAssertEqual(state.claude.arrangementTarget, one.id)
        state.layoutOutcome(.windowMissing(.claude), names: names)
        XCTAssertTrue(state.layoutProblem!.hasPrefix("Claude's window is gone."))
    }

    // MARK: Connect

    func testConnectingBothSidesInOrderReachesTheEditorWithEveryStepDone() throws {
        let state = try composed()
        XCTAssertEqual(state.phase, .compose)
        XCTAssertEqual(state.completed, Set(SetupStep.allCases))
        XCTAssertTrue(state.bothReady)
        XCTAssertNil(state.sendBlocker(names: names))
        XCTAssertEqual(state.progressDescription(names: names), "Setup complete: 4 of 4 steps done")
        XCTAssertEqual(state.chatgpt.connection?.context, "New chat")
        XCTAssertEqual(state.claude.connection?.name, "\u{201C}Errol brand naming\u{201D}")
        XCTAssertEqual(state.claude.connection?.context, "Continues here")
        XCTAssertEqual(state.claude.hint, DestinationHint(title: "Errol brand naming", surface: "Chat"),
                       "a named conversation is remembered; an unnamed one is not")
        XCTAssertNil(state.chatgpt.hint)
    }

    func testConnectingTheSecondSideFirstStillAsksForTheFirst() throws {
        var (state, gpt, cld) = try prepared()
        state.continueFromPrepare()
        state.choose(.keepPositions)
        state.layoutOutcome(.kept, names: names)
        state.continueFromArrange()
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))
        XCTAssertEqual(state.phase, .connect(.chatgpt))
        XCTAssertEqual(state.progress(of: .connectClaude), .done)
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .compose)
    }

    func testAWorkSurfaceIsADeliberateChoice() throws {
        var state = SetupState()
        let code = try candidate("claude-code-collapsed", selectors: claude)
        XCTAssertTrue(code.isEligible, "Claude allows a Code session when the human picks it")
        XCTAssertEqual(code.name, "Code session")
        state.connected(.claude, window: code.id, identity: code.identity, model: nil, observation: observation(code))
        XCTAssertEqual(state.claude.connection?.readiness, .needsSurfaceChoice("Code"))
        XCTAssertEqual(state.claude.connection?.readiness.problem(name: "Claude"),
                       "Claude is showing a Code session. Choose whether to use it.")
        state.acceptSurface(.claude)
        XCTAssertEqual(state.claude.connection?.readiness, .ready)
        // Later sweeps keep the acceptance.
        state.observe(.claude, binding: observation(code))
        XCTAssertEqual(state.claude.connection?.readiness, .ready)
    }

    func testADraftIsAFinishPreparingStepNotAConnectionLoss() throws {
        var state = try composed()
        let drafted = try candidate("chatgpt-chat-conversation", id: 1, selectors: chatgpt)
        XCTAssertEqual(drafted.composer, .draft(characters: 16))
        state.observe(.chatgpt, binding: observation(drafted))
        XCTAssertEqual(state.phase, .compose, "the connection stands; the draft is the human's to finish")
        XCTAssertEqual(state.chatgpt.connection?.readiness, .finishPreparing(.draft(side: .chatgpt, characters: 16)))
        XCTAssertEqual(state.chatgpt.connection?.readiness.status(name: "ChatGPT"), "Finish preparing")
        XCTAssertEqual(state.sendBlocker(names: names),
                       "ChatGPT has an unsent draft (16 characters). Finish or clear it, then send again.")
        XCTAssertEqual(state.chatgpt.connection?.identity.title, "Logo brainstorm",
                       "the identity follows the observation, so an adopted name shows")
        let home = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        state.observe(.chatgpt, binding: observation(home))
        XCTAssertNil(state.sendBlocker(names: names))
    }

    func testAChangedConversationBlocksSendingAndKeepsTheTopicSide() throws {
        var state = try composed()
        let claudeHome = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, binding: observation(claudeHome, check: .changed("showing a new chat")))
        XCTAssertEqual(state.phase, .compose)
        XCTAssertEqual(state.claude.connection?.readiness, .changed("showing a new chat"))
        XCTAssertEqual(state.sendBlocker(names: names),
                       "Claude is showing a new chat. Show the connected conversation again, or choose another.")
        XCTAssertTrue(state.chatgpt.isReady, "the other side is untouched")
    }

    func testALostConversationReopensOnlyThatSide() throws {
        var state = try composed()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        state.observe(.chatgpt, binding: observation(gpt, check: .lost("ChatGPT quit")))
        XCTAssertNil(state.chatgpt.connection)
        XCTAssertEqual(state.phase, .connect(.chatgpt))
        XCTAssertTrue(state.claude.isConnected)
        XCTAssertEqual(state.progress(of: .connectChatGPT), .current)
        XCTAssertEqual(state.progress(of: .connectClaude), .done)
        XCTAssertEqual(state.progress(of: .arrange), .done)
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .compose)
    }

    func testDisconnectingWhileConnectingTheOtherSideWaitsItsTurn() throws {
        var (state, gpt, cld) = try prepared()
        state.continueFromPrepare()
        state.choose(.keepPositions)
        state.layoutOutcome(.kept, names: names)
        state.continueFromArrange()
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .connect(.claude))
        state.disconnect(.chatgpt)
        XCTAssertEqual(state.phase, .connect(.chatgpt), "the first side comes first again")
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .connect(.claude))
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))
        XCTAssertEqual(state.phase, .compose)
    }

    // MARK: Return and restart

    func testReturningMarksBothConnectionsUnverifiedUntilObserved() throws {
        var state = try composed()
        state.runStarted()
        XCTAssertFalse(state.meterVisible)
        state.markUnverified()
        XCTAssertEqual(state.chatgpt.connection?.readiness, .unverified)
        XCTAssertEqual(state.chatgpt.connection?.readiness.status(name: "ChatGPT"), "Last used")
        XCTAssertEqual(state.sendBlocker(names: names), "Checking ChatGPT's conversation\u{2026}")
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let cld = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        state.observe(.chatgpt, binding: observation(gpt))
        state.observe(.claude, binding: observation(cld))
        XCTAssertNil(state.sendBlocker(names: names))
        XCTAssertFalse(state.meterVisible, "the ordinary return keeps the meter hidden")
    }

    func testFreshConversationsReconnectBothAndKeepTheAppsAndLayout() throws {
        var state = try composed()
        state.runStarted()
        state.reconnectBoth()
        XCTAssertEqual(state.phase, .connect(.chatgpt))
        XCTAssertFalse(state.bothConnected)
        XCTAssertEqual(state.completed, [.prepareApps, .arrange])
        XCTAssertTrue(state.meterVisible)
        XCTAssertEqual(state.claude.hint?.title, "Errol brand naming", "the last conversation stays a hint")
    }

    func testChangingTheLayoutLaterIsAPreferenceNotAReopenedStep() throws {
        var state = try composed()
        state.choose(.stacked)
        XCTAssertEqual(state.layout, .stacked)
        XCTAssertTrue(state.layoutApplied, "from the settings, the step stays done")
        XCTAssertEqual(state.progress(of: .arrange), .done)
        XCTAssertEqual(state.phase, .compose)
    }

    func testRestartKeepsOnlyTheHints() throws {
        var state = try composed()
        state.restart()
        XCTAssertEqual(state.phase, .prepareApps)
        XCTAssertTrue(state.completed.isEmpty)
        XCTAssertNil(state.claude.connection)
        XCTAssertEqual(state.claude.hint?.title, "Errol brand naming")
        XCTAssertEqual(state.claude.presence, .checking)
    }

    func testTheHintPointsThePickerAtTheRememberedWindow() throws {
        var side = SideSetup(side: .claude)
        let named = try candidate("claude-chat-conversation", id: 1, selectors: claude)
        let fresh = try candidate("claude-chat-home", id: 2, selectors: claude)
        side.candidates = [fresh, named]
        XCTAssertEqual(side.preferredCandidate?.id, fresh.id, "without a hint, the first eligible window")
        side.hint = DestinationHint(title: "Errol brand naming", surface: "Chat")
        XCTAssertEqual(side.preferredCandidate?.id, named.id)
        side.hint = DestinationHint(title: "Something else", surface: "Chat")
        XCTAssertEqual(side.preferredCandidate?.id, fresh.id, "a hint no window shows points nowhere")
    }

    func testHintsRoundTripThroughTheDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ErrolKitTests.hints.\(UUID().uuidString)"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        XCTAssertTrue(DestinationHints.load(from: defaults).isEmpty)
        DestinationHints.save(DestinationHint(title: "Logo brainstorm", surface: "Chat"), for: .chatgpt, in: defaults)
        XCTAssertEqual(DestinationHints.load(from: defaults)[.chatgpt],
                       DestinationHint(title: "Logo brainstorm", surface: "Chat"))
        DestinationHints.save(nil, for: .chatgpt, in: defaults)
        XCTAssertNil(DestinationHints.load(from: defaults)[.chatgpt])
    }
}

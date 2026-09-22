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
        XCTAssertEqual(AppPresence.notRunning.openState, "Click to open")
        XCTAssertEqual(AppPresence.noConversation.openState, "App open")
        XCTAssertTrue(AppPresence.noWindow.isOpen, "open asks nothing of the windows")
        XCTAssertFalse(AppPresence.launching.isOpen)
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

    func testContinueNeedsBothAppsOpenAndNothingOfTheirWindows() throws {
        var state = SetupState()
        let gpt = try candidate("chatgpt-chat-home", selectors: chatgpt)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .notRunning, candidates: [])
        XCTAssertFalse(state.continueFromPrepare())
        XCTAssertEqual(state.phase, .prepareApps)
        state.observe(.claude, presence: .launching, candidates: [])
        XCTAssertFalse(state.continueFromPrepare(), "opening is not open yet")
        state.observe(.claude, presence: .noConversation, candidates: [])
        XCTAssertTrue(state.bothOpen, "a running app is open, whatever its windows show")
        XCTAssertTrue(state.continueFromPrepare())
        XCTAssertEqual(state.phase, .arrange)
        XCTAssertEqual(state.progress(of: .prepareApps), .done)
        XCTAssertEqual(state.progress(of: .arrange), .current)
    }

    // MARK: Arrange

    func testTheLayoutAppliesAsChosenAndTheStepCompletesOnContinue() throws {
        var (state, _, _) = try prepared()
        state.continueFromPrepare()
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
        XCTAssertEqual(state.progress(of: .arrange), .current, "arranging does not complete the step; continuing does")
        state.choose(.keepPositions)
        XCTAssertTrue(state.layoutApplied)
        XCTAssertTrue(state.continueFromArrange())
        XCTAssertEqual(state.progress(of: .arrange), .done)
        XCTAssertEqual(state.phase, .connect(.chatgpt), "ChatGPT connects first, whoever starts")
        XCTAssertFalse(state.continueFromArrange(), "only from the arrange step")
    }

    func testContinueIsOfferedWhateverTheArrangementDid() throws {
        var (state, _, _) = try prepared()
        state.continueFromPrepare()
        state.choose(.stacked)
        XCTAssertTrue(state.continueFromArrange(), "a move still in flight is the controller's to wait on")
        var (again, _, _) = try prepared()
        again.continueFromPrepare()
        again.choose(.stacked)
        again.layoutOutcome(.windowMissing(.claude))
        XCTAssertFalse(again.layoutApplied)
        XCTAssertNil(again.layoutProblem, "the sweep says what to open; the layout applies again once it is there")
        XCTAssertTrue(again.continueFromArrange(), "the windows are as they are, which is somewhere to go on from")
        XCTAssertEqual(again.progress(of: .arrange), .done)
    }

    func testSeveralWindowsNeedAnExplicitOneBeforeArranging() throws {
        var state = SetupState()
        let one = try candidate("claude-chat-conversation", id: 1, selectors: claude)
        let two = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, presence: .available(windows: 2), candidates: [one, two])
        XCTAssertNil(state.claude.arrangementTarget)
        XCTAssertTrue(state.claude.needsArrangementChoice)
        XCTAssertFalse(state.needsArrangementChoice(.claude), "nothing to choose while nothing moves")
        state.choose(.stacked)
        XCTAssertTrue(state.needsArrangementChoice(.claude))
        state.chooseArrangementWindow(.claude, two.id)
        XCTAssertEqual(state.claude.arrangementTarget, two.id)
        XCTAssertFalse(state.claude.needsArrangementChoice)
        // A connection outranks the choice.
        state.connected(.claude, window: one.id, identity: one.identity, model: nil, observation: observation(one))
        XCTAssertEqual(state.claude.arrangementTarget, one.id)
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
        state.continueFromArrange()
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))
        XCTAssertEqual(state.phase, .connect(.chatgpt))
        XCTAssertEqual(state.progress(of: .connectClaude), .done)
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .compose)
    }

    func testAWorkSurfaceConnectsLikeAnyConversation() throws {
        // An existing Code session is a place the human chose on purpose: it
        // is named as one under the icon and asks for no further choice.
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

    func testAHiddenWindowBlocksSendingAndKeepsTheOtherSide() throws {
        var state = try composed()
        let claudeHome = try candidate("claude-chat-home", id: 2, selectors: claude)
        state.observe(.claude, binding: observation(claudeHome, check: .hidden("minimized")))
        XCTAssertEqual(state.phase, .compose, "the connection stands; the window is the human's to bring back")
        XCTAssertEqual(state.claude.connection?.readiness, .hidden("minimized"))
        XCTAssertEqual(state.claude.connection?.readiness.status(name: "Claude"), "Hidden")
        XCTAssertEqual(state.sendBlocker(names: names), "Claude's window is minimized. Bring it back to send.")
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

    func testProgressNavigationPreservesSetupAndStopsAutomaticReturn() throws {
        var state = try composed()
        let original = state
        XCTAssertTrue(state.revisit(.prepareApps))
        XCTAssertFalse(state.automaticallyContinuePreparation)
        XCTAssertEqual(state.progress(of: .prepareApps), .current)
        XCTAssertEqual(state.completed, original.completed)
        XCTAssertEqual(state.chatgpt, original.chatgpt)
        XCTAssertEqual(state.claude, original.claude)
        XCTAssertEqual(state.layout, original.layout)
        XCTAssertTrue(state.continueFromPrepare())
        XCTAssertTrue(state.continueFromArrange())
        XCTAssertEqual(state.phase, .compose, "existing connections do not need rebinding")
        state.restart()
        XCTAssertTrue(state.automaticallyContinuePreparation, "fresh setup restores its countdown")
    }

    func testProgressNavigationOnlyOffersEarlierAvailableSteps() throws {
        var (state, _, _) = try prepared()
        XCTAssertFalse(state.revisit(.prepareApps), "the current segment is not a cancel button")
        XCTAssertFalse(state.revisit(.arrange), "the bar cannot skip ahead")
        state.continueFromPrepare()
        state.continueFromArrange()
        XCTAssertTrue(state.canRevisit(.arrange))
        XCTAssertFalse(state.canRevisit(.connectClaude))
        state.observe(.claude, presence: .notRunning, candidates: [])
        XCTAssertFalse(state.revisit(.arrange), "later screens still require both apps open")
        XCTAssertTrue(state.revisit(.prepareApps))
        var running = try composed()
        XCTAssertTrue(running.canRevisit(.prepareApps))
        running.runStarted()
        XCTAssertFalse(running.canRevisit(.prepareApps), "a run's hidden meter cannot reopen setup")
    }

    func testRevisitedConnectionCanContinueWithItsExistingBinding() throws {
        var state = try composed()
        let connection = state.chatgpt.connection
        XCTAssertTrue(state.revisit(.connectChatGPT))
        XCTAssertEqual(state.progress(of: .connectChatGPT), .current)
        XCTAssertEqual(state.chatgpt.connection, connection)
        XCTAssertTrue(state.continueFromConnection())
        XCTAssertEqual(state.phase, .compose)
        state.disconnect(.chatgpt)
        XCTAssertFalse(state.continueFromConnection(), "a lost connection must be chosen again")
    }

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
        XCTAssertFalse(state.layoutApplied, "applied by its own command, from the settings")
        XCTAssertEqual(state.progress(of: .arrange), .done, "the step stays done")
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

    // MARK: The direct console

    func testTheDirectConsoleStartsAtTheEditorAndAsksForTheApps() {
        var state = SetupState.direct()
        XCTAssertEqual(state.phase, .compose)
        XCTAssertFalse(state.meterVisible)
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

    func testOnlyASideWithOneUsableWindowIsConnectedForIt() throws {
        var state = SetupState.direct()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let named = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        let fresh = try candidate("claude-chat-home", id: 3, selectors: claude)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .available(windows: 2), candidates: [named, fresh])
        state.claude.hint = DestinationHint(title: "Errol brand naming", surface: "Chat")

        XCTAssertEqual(state.automaticConnection(for: .chatgpt), gpt.id)
        XCTAssertNil(state.automaticConnection(for: .claude), "several windows are never chosen among, hint or not")
        XCTAssertTrue(state.needsConversationChoice(.claude))
        XCTAssertEqual(state.notice(names: names)?.text, "Connecting ChatGPT\u{2026}")

        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        XCTAssertEqual(state.phase, .compose, "the editor stays while the other side is unconnected")
        XCTAssertNil(state.automaticConnection(for: .chatgpt), "a connected side is left alone")
        XCTAssertEqual(state.notice(names: names)?.text,
                       "Claude has 2 conversations open. Click its icon to choose one.")

        state.connected(.claude, window: named.id, identity: named.identity, model: nil,
                        observation: observation(named))
        XCTAssertNil(state.notice(names: names))
        XCTAssertNil(state.sendBlocker(names: names))

        var guided = SetupState()
        guided.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        XCTAssertNil(guided.automaticConnection(for: .chatgpt), "the guided flow connects by the drag alone")
    }

    func testALostConversationKeepsTheDirectConsoleOnTheEditor() throws {
        var state = SetupState.direct()
        let gpt = try candidate("chatgpt-chat-home", id: 1, selectors: chatgpt)
        let cld = try candidate("claude-chat-conversation", id: 2, selectors: claude)
        state.observe(.chatgpt, presence: .available(windows: 1), candidates: [gpt])
        state.observe(.claude, presence: .available(windows: 1), candidates: [cld])
        state.connected(.chatgpt, window: gpt.id, identity: gpt.identity, model: nil, observation: observation(gpt))
        state.connected(.claude, window: cld.id, identity: cld.identity, model: nil, observation: observation(cld))

        state.observe(.claude, binding: observation(cld, check: .lost("the window closed")))
        XCTAssertEqual(state.phase, .compose)
        XCTAssertNil(state.claude.connection)
        XCTAssertNotNil(state.chatgpt.connection, "the other side keeps its conversation")
        XCTAssertEqual(state.automaticConnection(for: .claude), cld.id)

        state.restart()
        XCTAssertFalse(state.guided, "starting over stays in the flow it was in")
        XCTAssertEqual(state.phase, .compose)
    }
}

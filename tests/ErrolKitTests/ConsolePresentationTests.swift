import XCTest
@testable import ErrolKit

final class ConsolePresentationTests: XCTestCase {
    func testFocusActionsWaitForGrantedPause() {
        var access = ConsoleAccess(running: true, steering: false, pending: false, stopping: false,
                                   showingWindow: false, focusOperationActive: true)
        XCTAssertFalse(access.canShowWindow)
        XCTAssertFalse(access.canTakeFocus)
        access.focusOperationActive = false
        XCTAssertTrue(access.canTakeFocus, "Keyboard users can read controls between handoffs")
        XCTAssertFalse(access.canShowWindow, "External window activation still requires a hold")
        access.pending = true
        XCTAssertFalse(access.canShowWindow)
        access.steering = true
        XCTAssertFalse(access.canShowWindow, "A pending grant still belongs to the worker")
        access.pending = false
        XCTAssertTrue(access.canShowWindow)
        XCTAssertTrue(access.canResume)
        XCTAssertFalse(access.canChangeDestination)
        access.showingWindow = true
        XCTAssertFalse(access.canResume, "The hold cannot lift during a window activation")
        XCTAssertFalse(access.canShowWindow)
        access.stopping = true
        XCTAssertFalse(access.canResume)
        access.running = false
        access.stopping = false
        XCTAssertFalse(access.canChangeDestination, "A completed run must wait for an outstanding window action")
        access.showingWindow = false
        XCTAssertTrue(access.canChangeDestination)
        XCTAssertTrue(access.canShowWindow)
    }

    func testOutcomeSymbolsAndDestinationWarnings() {
        XCTAssertEqual(RunOutcome.completed.symbol, "checkmark.circle.fill")
        for outcome in [RunOutcome.stopped, .turnLimitReached] {
            XCTAssertFalse(outcome.needsAttention)
            XCTAssertNotEqual(outcome.symbol, RunOutcome.completed.symbol)
        }
        for outcome in [RunOutcome.timedOut(side: .claude), .copyFailed(side: .claude),
                        .sendRefused(side: .claude), .sendAbandoned(side: .claude),
                        .emptyReply(side: .claude), .destinationLost(side: .claude, detail: "closed")] {
            XCTAssertTrue(outcome.needsAttention)
            XCTAssertEqual(outcome.attentionSide, .claude)
            XCTAssertNotNil(outcome.shortStatus)
        }
        XCTAssertEqual(RunOutcome.sendAbandoned(side: .claude).shortStatus, "check delivery")
    }

    func testDestinationDescribesCurrentWindowRatherThanOriginalChat() {
        let window = WindowID(raw: 42)
        let original = DestinationIdentity(title: "Original topic", titleIsGeneric: false, surface: "Chat")
        var side = SideSetup(side: .claude)
        side.connection = SideConnection(window: window, identity: original, model: "Old model")
        XCTAssertEqual(side.destinationName, "“Original topic”")
        var scan = WindowScan()
        scan.title = "Different topic in the same window"
        scan.hasComposer = true
        scan.messageAffordances = 4
        var current = WindowCandidate(id: window, scan: scan, selectors: config.claudeSelectors)
        current.identity.surface = "Cowork"
        current.model = "Current model · High"
        side.candidates = [current]
        XCTAssertEqual(side.destinationName, "“Different topic in the same window”")
        XCTAssertEqual(side.destinationSurface, "Cowork")
        XCTAssertEqual(side.destinationModel, "Current model · High")
        XCTAssertEqual(side.destinationContext, "Continues here")
    }

    func testAllThemeTextPairsMeetNormalTextContrast() {
        for theme in AppTheme.allCases {
            for (appearance, colors) in [("light", theme.consolePalette.light), ("dark", theme.consolePalette.dark)] {
                let pairs: [(String, UInt32, UInt32)] = [
                    ("ink/paper", colors.ink, colors.paper),
                    ("secondary/paper", colors.secondary, colors.paper),
                    ("placeholder/paper", colors.placeholder, colors.paper),
                    ("accentText/paper", colors.accentText, colors.paper),
                    ("muted/paper", colors.muted, colors.paper),
                    ("muted/well", colors.muted, colors.well),
                    ("secondary/well", colors.secondary, colors.well),
                    ("ink/well", colors.ink, colors.well),
                    ("accentText/well", colors.accentText, colors.well),
                    ("onAccent/accent", colors.onAccent, colors.accent),
                    ("red/paper", colors.red, colors.paper),
                    ("red/well", colors.red, colors.well),
                ]
                for (pair, foreground, background) in pairs {
                    let light = luminance(foreground), dark = luminance(background)
                    let contrast = (max(light, dark) + 0.05) / (min(light, dark) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(theme) \(appearance) \(pair): \(contrast)")
                }
            }
        }
    }

    private func luminance(_ hex: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let s = Double((hex >> shift) & 255) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}

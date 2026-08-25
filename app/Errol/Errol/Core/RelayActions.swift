// The copy/send/wait primitives one turn of the relay is built from.

import AppKit
import ApplicationServices

/// Cmd+N opens a fresh conversation in both apps (reusing the window).
/// Confirmed fresh when no per-message copy buttons remain in the chat window.
func startNewChat(in target: TargetApp) -> Bool {
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front for Cmd+N")
        return false
    }
    keystroke(keyN, flags: .maskCommand)
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if copyButtons(in: target).isEmpty {
            log("\(target.name): new chat ready")
            return true
        }
        usleep(200_000)
    }
    log("\(target.name): WARNING: could not confirm a fresh chat, continuing in the current one")
    return true
}

func copyLastResponse(from target: TargetApp) -> String? {
    let buttons = copyButtons(in: target)
    guard let button = buttons.last else {
        log("\(target.name): no copy button found")
        return nil
    }
    let pasteboard = NSPasteboard.general
    let before = pasteboard.changeCount
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    if err != .success {
        log("\(target.name): AXPress on copy button failed (\(err.rawValue))")
        return nil
    }
    let deadline = Date().addingTimeInterval(3)
    while pasteboard.changeCount == before {
        if Date() > deadline {
            log("\(target.name): clipboard never changed after pressing copy")
            return nil
        }
        usleep(50_000)
    }
    return pasteboard.string(forType: .string)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func send(_ text: String, to target: TargetApp) -> Bool {
    var payload = text
    if payload.count > config.maxChars {
        payload = String(payload.prefix(config.maxChars)) + "\n\n[truncated by relay]"
        log("\(target.name): payload truncated to \(config.maxChars) chars")
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(payload, forType: .string)

    // Keystrokes go to the frontmost app no matter what has AX focus, so
    // never type unless the target is verified frontmost.
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front; refusing to type into another app's window")
        return false
    }

    if let input = inputArea(in: target) {
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(150_000)
    } else {
        log("\(target.name): could not locate input area, pasting into current focus")
    }

    keystroke(keyV, flags: .maskCommand)
    // Give the app time to render the paste; large messages need it before sending.
    let renderDelay = min(2_000_000, 300_000 + payload.count * 20)
    usleep(useconds_t(renderDelay))

    let beforeSend = composerValue(in: target)

    // A send button press is more reliable than a Return keystroke (no
    // Return-vs-Cmd+Return ambiguity, no dependence on keyboard focus).
    if let button = sendButton(in: target),
       AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
        log("\(target.name): sent via send button")
    } else {
        keystroke(keyReturn)
        log("\(target.name): sent via Return keystroke")
    }

    // Confirm the composer emptied; if not, escalate through the known
    // variants, re-checking frontmost before each keystroke so an app that
    // stole focus mid-send doesn't receive stray Returns.
    if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
        guard isFrontmost(target) else {
            log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
            return false
        }
        log("\(target.name): composer unchanged after send, trying Return keystroke")
        keystroke(keyReturn)
        if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
            guard isFrontmost(target) else {
                log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
                return false
            }
            log("\(target.name): composer still unchanged, trying Cmd+Return")
            keystroke(keyReturn, flags: .maskCommand)
            if !waitForComposerChange(in: target, from: beforeSend, within: 3) {
                log("\(target.name): WARNING: could not confirm the message was sent")
            }
        }
    }
    return true
}

func waitForComposerChange(in target: TargetApp, from before: String?, within seconds: TimeInterval) -> Bool {
    // Composer value can be unreadable in some states; then there is nothing to verify.
    guard before != nil else { return true }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if composerValue(in: target) != before { return true }
        usleep(200_000)
    }
    return false
}

/// Both apps give the just-pasted user message its own copy button, so a raw
/// "count went up" check fires on the echo of our own message. Wait for that
/// echo to render and fold it into the baseline; only buttons beyond it can
/// belong to the response.
func absorbEchoIntoBaseline(in target: TargetApp, preSend: Int) -> Int {
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if copyButtons(in: target).count > preSend { return preSend + 1 }
        usleep(100_000)
    }
    return preSend
}

func waitForResponse(in target: TargetApp, baselineCopyCount: Int) -> Bool {
    log("\(target.name): waiting for response (baseline \(baselineCopyCount) copy buttons)...")
    let deadline = Date().addingTimeInterval(config.timeout)
    var stableTicks = 0
    while Date() < deadline {
        if relayCancelled.isSet { return false }
        let count = copyButtons(in: target).count
        let streaming = hasStopButton(in: target)
        if count > baselineCopyCount && !streaming {
            stableTicks += 1
            if stableTicks >= 2 {
                log("\(target.name): response complete (\(count) copy buttons)")
                return true
            }
        } else {
            stableTicks = 0
        }
        usleep(1_200_000)
    }
    log("\(target.name): timed out after \(Int(config.timeout))s")
    return false
}

// Synthesized keystrokes. These go to the frontmost app no matter what has
// AX focus — hence the verified-activation safeguards in Activation.swift.

import CoreGraphics
import Foundation

func keystroke(_ virtualKey: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(30_000)
    let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
}

let keyV: CGKeyCode = 9
let keyN: CGKeyCode = 45
let keyReturn: CGKeyCode = 36

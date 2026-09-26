// Where people turn on the permission Errol runs on, in the words System
// Settings uses. macOS 27 renamed Privacy & Security's Accessibility list to
// Device Control and Data Access. The permission, the AX calls that need it,
// and the settings link are the same as before, so only the words change.

import Foundation

enum AccessPermission {
    /// Whether this system uses the macOS 27 name.
    static var isRenamed: Bool {
        if #available(macOS 27, *) { return true }
        return false
    }

    /// The list's name in Privacy & Security, where Errol's switch is.
    static var listName: String {
        isRenamed ? "Device Control and Data Access" : "Accessibility"
    }

    /// The way to that list, for a sentence to point at.
    static var settingsPath: String {
        "System Settings \u{203A} Privacy & Security \u{203A} \(listName)"
    }
}

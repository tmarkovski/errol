// The update's state, as the console's Update button and the status item's
// menu show it. UpdaterController drives it from Sparkle.

import Foundation
import Observation

/// What the console and the status item's menu show about an update. Only
/// UpdaterController writes it; it lives apart from that file so the render
/// harness (tools/console-preview), which builds without Sparkle, can draw
/// the button.
@Observable
final class UpdateStatus {
    static let shared = UpdateStatus()

    enum Phase: Equatable {
        case idle
        /// A check the user asked for is out.
        case checking
        /// Found and waiting for a click, which downloads it and relaunches.
        case available(version: String)
        /// Downloading and unpacking after a click or a manual check.
        case preparing(version: String)
        /// Staged: a click relaunches into it, and quitting installs it.
        case ready(version: String)
        case restarting
    }

    /// The answer to a check the user asked for, when there is no update to
    /// offer. It clears itself after a few seconds.
    enum Note: Equatable {
        case upToDate
        case problem(String)
    }

    var phase = Phase.idle
    var note: Note?

    /// The version on offer, while there is one.
    var version: String? {
        switch phase {
        case .available(let version), .preparing(let version), .ready(let version): version
        case .idle, .checking, .restarting: nil
        }
    }

    /// Whether a click on the button, or the menu entry, does something now.
    var canAct: Bool {
        switch phase {
        case .available, .ready: true
        case .idle, .checking, .preparing, .restarting: false
        }
    }

    @ObservationIgnored var perform: () -> Void = {}
    @ObservationIgnored private var noteCount = 0

    /// The button's click: download and relaunch, or relaunch into what is
    /// already staged.
    func update() { perform() }

    #if DEBUG
    /// A stand-in for the canvases (PerchPreviews+Update), in the given phase. A
    /// click walks it on the way the real one goes: an offer downloads for
    /// a moment and becomes ready, and ready restarts for a moment and
    /// comes back.
    static func preview(_ phase: Phase, note: Note? = nil) -> UpdateStatus {
        let status = UpdateStatus()
        status.phase = phase
        status.note = note
        status.perform = { [weak status] in
            guard let status, let version = status.version else { return }
            let settled: Phase = .ready(version: version)
            switch status.phase {
            case .available: status.phase = .preparing(version: version)
            case .ready: status.phase = .restarting
            default: return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { status.phase = settled }
        }
        return status
    }
    #endif

    /// A note that clears itself after a few seconds.
    func show(_ note: Note) {
        self.note = note
        noteCount += 1
        let count = noteCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.noteCount == count else { return }
            self.note = nil
        }
    }
}

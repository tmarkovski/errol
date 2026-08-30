// Auto-update, arranged so it can never interrupt a relay.
//
// Errol is unusual among menu bar apps in two ways that shape this file. It
// holds an Accessibility grant that macOS keys to the app's code signature, so
// an update that changes the signing identity would silently strip the
// permission the app needs to do anything — the release pipeline guards that
// side (see scripts/verify-artifact.sh). And a run owns the screen focus and
// the clipboard for minutes at a time, so an update that showed a window or
// relaunched the app mid-run would destroy the conversation in progress.
//
// The contract, in order of how often it matters:
//
//   - Checking and downloading in the background during a run is fine. Neither
//     touches focus.
//   - Presenting anything is not. A scheduled update found mid-run is held
//     back and offered when the run ends.
//   - A manual check is refused while a run is live, rather than queued.
//   - A relaunch Sparkle asks for mid-run is postponed until the run is idle.
//   - Termination cancels a run first, so the transcript is flushed and focus
//     handed back before an install-on-quit takes over.
//
// Installation stays user-mediated in this version: SUAutomaticallyUpdate and
// SUAllowsAutomaticUpdates are both off in Info.plist. The guards here are the
// second layer, not the only one.

import AppKit
import Sparkle

final class UpdaterController: NSObject {
    /// Sparkle's own controller. Started immediately: background checks are
    /// wanted from launch, and everything that could interrupt a run is gated
    /// by the delegate callbacks below rather than by withholding the updater.
    private var controller: SPUStandardUpdaterController!

    /// Asked, rather than stored, so this type never holds a stale copy of the
    /// relay's state — the run can end between a check starting and finishing.
    private let relayIsRunning: () -> Bool

    /// Set when Sparkle asked to relaunch during a run. Calling it installs the
    /// update that was already downloaded and staged.
    private var postponedInstall: (() -> Void)?

    /// An update that arrived while a run was live and was not presented. Held
    /// so the end of the run can offer it instead of silently dropping it.
    private(set) var deferredUpdate: SUAppcastItem?

    init(relayIsRunning: @escaping () -> Bool) {
        self.relayIsRunning = relayIsRunning
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self)
    }

    /// Drives the menu item's enabled state. A run in progress disables the
    /// manual check outright — queueing it would only surface a window later,
    /// at a moment the user did not choose.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates && !relayIsRunning()
    }

    func checkForUpdates() {
        guard !relayIsRunning() else { return }
        // LSUIElement means no Dock icon, so Sparkle's window would open behind
        // whatever is frontmost with nothing to click to reach it. Activation
        // is safe here precisely because no run is live.
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    /// Called when a run reaches idle. Anything held back during the run is
    /// released here: the staged install first, since it is already downloaded,
    /// otherwise the update that was found but never shown.
    func relayDidFinish() {
        if let install = postponedInstall {
            postponedInstall = nil
            install()
            return
        }
        guard deferredUpdate != nil else { return }
        deferredUpdate = nil
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterController: SPUUpdaterDelegate {
    /// The relaunch guard. Returning true hands Sparkle's install block back to
    /// us to invoke later; relayDidFinish() is what invokes it.
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard relayIsRunning() else { return false }
        postponedInstall = installHandler
        return true
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdaterController: SPUStandardUserDriverDelegate {
    /// Opting into gentle reminders is what makes the next callback consulted
    /// at all. Without it Sparkle presents scheduled updates on its own
    /// schedule, which is the behavior a run cannot survive.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Returning false means "not now, and I take responsibility for it" —
    /// which is why deferredUpdate is recorded rather than dropped.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        guard relayIsRunning() else { return true }
        deferredUpdate = update
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Only bring the app forward when Sparkle is actually about to put
        // something on screen, and only when nothing is running. Activating
        // unconditionally would itself be the focus theft this file exists to
        // prevent.
        guard handleShowingUpdate, !relayIsRunning() else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillShowModalAlert() {
        guard !relayIsRunning() else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}

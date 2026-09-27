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
// Sparkle does the checking, verifying, downloading, and installing; this file
// is its user driver, so none of Sparkle's windows ever appear. What the user
// sees is UpdateStatus: an Update button beside the console's ··· menu, and
// the status item's menu entry, both of which follow the update's phase.
//
// The flow, in order of how often it matters:
//
//   - Every six hours (SUScheduledCheckInterval) Sparkle checks, and with
//     SUAutomaticallyUpdate on it downloads and stages a new version in the
//     background. Neither touches focus, so both are fine during a run.
//   - A staged update installs whenever Errol quits. Until then the Update
//     button offers it, and a click relaunches into it at once.
//   - When Sparkle can't stage on its own (the install needs an admin's
//     password, say), the button offers the update instead, and a click
//     downloads it and relaunches.
//   - "Check for Updates…" checks and downloads; the button then offers the
//     relaunch. Finding nothing leaves a short note beside the ··· menu.
//   - While a run is live the button is hidden, the menu entry is disabled,
//     and a relaunch Sparkle asks for is postponed until the run is idle.
//     Termination cancels a run first, so it winds down at a safe point and
//     the debug log closes before an install-on-quit takes over.
//
// A debug build leaves the updater stopped (see updatesEnabled).

import AppKit
import Sparkle

final class UpdaterController: NSObject {
    #if DEBUG
    /// A debug build is build 1 (CURRENT_PROJECT_VERSION), older than every
    /// published build, so each check would find an update, download it, and
    /// install it on quit over the Xcode build product, taking its signature
    /// and the Accessibility grant with it. It updates only when asked to, as
    /// when trying this flow against a rehearsal feed:
    ///   defaults write com.t7m8.Errol ErrolDebugUpdates -bool YES
    private static let updatesEnabled = UserDefaults.standard.bool(forKey: "ErrolDebugUpdates")
    #else
    private static let updatesEnabled = true
    #endif

    private var updater: SPUUpdater!
    private let status = UpdateStatus.shared

    /// Asked, rather than stored, so this type never holds a stale copy of the
    /// relay's state — the run can end between a check starting and finishing.
    private let relayIsRunning: () -> Bool

    /// Brings the console forward, where the button and the notes are, when
    /// a check is asked for again while an update is already on offer.
    var bringConsoleForward: () -> Void = {}

    /// Set when Sparkle asked to relaunch during a run. Calling it installs the
    /// update that was already downloaded and staged.
    private var postponedInstall: (() -> Void)?

    /// Installs the update Sparkle staged in the background and relaunches.
    private var stagedInstall: (() -> Void)?

    /// Sparkle's question about the update on offer — install, dismiss, or
    /// skip — held until the button is clicked. Only one is ever pending.
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?

    /// The button was clicked for an update that still had to download, so
    /// the relaunch follows as soon as it is ready.
    private var relaunchWhenReady = false

    /// For an update the feed only announces, with a page instead of a
    /// download: the button opens the page.
    private var infoURL: URL?

    private var offeredVersion = ""

    init(relayIsRunning: @escaping () -> Bool) {
        self.relayIsRunning = relayIsRunning
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        status.perform = { [weak self] in self?.update() }
        // Left unstarted, the updater never checks, and canCheckForUpdates
        // keeps the menu entry disabled.
        guard Self.updatesEnabled else { return }
        do {
            try updater.start()
        } catch {
            // A development build run outside a signed bundle can't update;
            // the menu entry stays disabled through canCheckForUpdates.
            print("Updater failed to start: \(error.localizedDescription)")
        }
    }

    // MARK: The menu entry

    /// The status item's entry: a check while nothing is on offer, and the
    /// same action as the button once something is.
    var menuTitle: String {
        switch status.phase {
        case .idle: "Check for Updates…"
        case .checking: "Checking for Updates…"
        case .available(let version): "Update to Errol \(version)"
        case .preparing(let version): "Updating to Errol \(version)…"
        case .ready(let version): "Restart to Update to Errol \(version)"
        case .restarting: "Restarting…"
        }
    }

    /// A run in progress disables the entry outright: a check could only
    /// end in a relaunch the run can't survive.
    var menuEnabled: Bool {
        guard !relayIsRunning() else { return false }
        switch status.phase {
        case .idle: return updater.canCheckForUpdates
        case .available, .ready: return true
        case .checking, .preparing, .restarting: return false
        }
    }

    func menuItemChosen() {
        if status.canAct { update() } else { checkForUpdates() }
    }

    func checkForUpdates() {
        guard !relayIsRunning() else { return }
        updater.checkForUpdates()
    }

    /// Called when a run reaches idle: a relaunch Sparkle asked for during
    /// the run goes ahead now. Anything else it found is already on the
    /// button, which comes back as the run ends.
    func relayDidFinish() {
        guard let install = postponedInstall else { return }
        postponedInstall = nil
        install()
    }

    // MARK: The button

    private func update() {
        guard !relayIsRunning(), status.canAct else { return }
        if let url = infoURL {
            infoURL = nil
            NSWorkspace.shared.open(url)
            answer(.dismiss)
            status.phase = .idle
            return
        }
        if let install = stagedInstall {
            status.phase = .restarting
            install()
            return
        }
        if case .ready = status.phase {
            status.phase = .restarting
        } else {
            status.phase = .preparing(version: offeredVersion)
            relaunchWhenReady = true
        }
        answer(.install)
    }

    private func answer(_ choice: SPUUserUpdateChoice) {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        reply(choice)
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

    /// A background download is staged. Returning true keeps it for the
    /// button to install on a click; it installs on quit either way.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        offeredVersion = item.displayVersionString
        stagedInstall = immediateInstallHandler
        status.phase = .ready(version: offeredVersion)
        return true
    }
}

// MARK: - SPUUserDriver

extension UpdaterController: SPUUserDriver {
    /// Never asked in practice: SUEnableAutomaticChecks in Info.plist answers
    /// it already. The same answer, in case a defaults reset brings it back.
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        status.phase = .checking
        status.note = nil
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offeredVersion = appcastItem.displayVersionString
        if appcastItem.isInformationOnlyUpdate {
            infoURL = appcastItem.infoURL
            pendingReply = reply
            status.phase = .available(version: offeredVersion)
            return
        }
        switch state.stage {
        case .installing:
            // Staged already; installing now is the fast relaunch.
            pendingReply = reply
            status.phase = .ready(version: offeredVersion)
        case .notDownloaded, .downloaded:
            if state.userInitiated, !relayIsRunning() {
                // Asked for: fetch it now, and offer the relaunch when ready.
                status.phase = .preparing(version: offeredVersion)
                reply(.install)
            } else {
                pendingReply = reply
                status.phase = .available(version: offeredVersion)
            }
        @unknown default:
            pendingReply = reply
            status.phase = .available(version: offeredVersion)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        status.phase = .idle
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? Int32
        switch reason.flatMap(SPUNoUpdateFoundReason.init(rawValue:)) {
        case .onLatestVersion, .onNewerThanLatestVersion:
            status.show(.upToDate)
        default:
            status.show(.problem(error.localizedDescription))
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        relaunchWhenReady = false
        pendingReply = nil
        status.phase = stagedInstall == nil ? .idle : .ready(version: offeredVersion)
        // Declining the password prompt is a choice, not a failure.
        if (error as NSError).code != Int(SUError.installationCanceledError.rawValue) {
            status.show(.problem(error.localizedDescription))
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        status.phase = .preparing(version: offeredVersion)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    /// After a click, the relaunch follows at once. After a manual check, the
    /// button offers it, so nobody is restarted without asking.
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if relaunchWhenReady, !relayIsRunning() {
            relaunchWhenReady = false
            status.phase = .restarting
            reply(.install)
            return
        }
        relaunchWhenReady = false
        pendingReply = reply
        status.phase = .ready(version: offeredVersion)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        status.phase = .restarting
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        bringConsoleForward()
    }

    /// The session ended or was abandoned. A staged update outlives it: it
    /// still installs on quit, so the button keeps offering it.
    func dismissUpdateInstallation() {
        pendingReply = nil
        relaunchWhenReady = false
        infoURL = nil
        if stagedInstall != nil {
            status.phase = .ready(version: offeredVersion)
        } else if status.phase != .restarting {
            status.phase = .idle
        }
    }
}

// The seam between the panel's model and the machinery that drives the
// apps. RelayController owns what the panel shows; an engine owns
// everything that reaches outside the process — the Accessibility
// permission, the two apps, the readiness sweeps, the relay worker, the
// microphone — and reports back over its event stream. This file holds
// only the protocol. The app runs LiveRelayEngine (LiveRelayEngine.swift).
// The canvases run PerchPreviewEngine
// (Perch/Previews/PerchPreviewEngine.swift), which plays a run without
// touching any app, so a preview's Start starts something and its Stop
// stops it while nothing is relayed anywhere.
//
// Setup goes through the same seam: the engine opens an app, offers the
// windows it finds, binds the one the human chose, arranges the two, and
// runs the relay into exactly those windows. The live elements never
// leave the engine — the model sees WindowIDs and observations — so a
// saved preference can never masquerade as a live connection.

import Foundation

protocol RelayEngine: AnyObject {
    /// The engine's outward stream. The controller subscribes once; the
    /// engine posts from wherever its work happens, and delivery is on the
    /// main thread in posting order (RelayEventBus).
    var events: RelayEventBus { get }
    /// The inward flags and mailbox: cancel, pause, the steering note. The
    /// controller writes them; the run reads them at its boundaries.
    var control: RelayControl { get }
    /// Readiness sweeps report here, on whatever thread the sweep ran:
    /// each side's status for the console, the windows each app offers,
    /// and how each bound conversation reads now.
    var onReadiness: ((ReadinessReport) -> Void)? { get set }
    /// Whether to sweep at all: only while someone can see the console.
    /// The scanner starts no sweep while a run owns the apps; a sweep
    /// already in flight finishes, read-only, alongside the run's first
    /// steps.
    func setScanning(_ scanning: Bool)
    /// Ask for a prompt sweep — a side to connect again, a return to the
    /// editor — rather than waiting out the interval.
    func requestSweep()
    /// Whether a run can start now: the permission is granted and both
    /// sides are bound. What is missing is reported as a failed start on
    /// the event stream. May prompt (the Accessibility dialog), which is
    /// why it is asked at Send and not at launch.
    func preflight() -> Bool
    /// Start the run, with the settings config holds (seed, turns, first
    /// speaker), into the bound windows, on the engine's own worker. It
    /// ends with `.finished` on the event stream, after every line it
    /// logged. Called after a preflight that passed.
    func startRun()
    #if DEBUG
    /// The debug dump of both apps' windows, buttons, and selector matches
    /// into the log. Does its own preflight. A debug build's Inspect Apps
    /// item is the only way to it.
    func inspect()
    #endif
    /// What hears the microphone for the prompt box's mic button
    /// (VoiceInput.swift): SpeechTranscriber in the app, a script in the
    /// canvases, which never open the microphone.
    var transcriber: VoiceTranscriber { get }

    // MARK: Setup

    /// Open the app. false when it is not installed, in which case nothing
    /// is opened.
    func launch(_ side: Speaker) -> Bool
    /// Bring the app forward — its bound window first, where it has one —
    /// and say when it is there, on the main thread, so the console can
    /// take the keyboard back. Answered anyway, after a bounded wait, for
    /// an app that will not come.
    func bringForward(_ side: Speaker, completion: @escaping () -> Void)
    /// Bind `window` as the side's destination. The observation arrives on
    /// the main thread; nil when the window is gone.
    func bind(_ side: Speaker, to window: WindowID, completion: @escaping (BindingObservation?) -> Void)
    func unbind(_ side: Speaker)
    /// Apply a layout to the two windows, ChatGPT first. Answered on the
    /// main thread.
    func arrange(_ layout: LayoutChoice, windows: [Speaker: WindowID],
                 completion: @escaping (ArrangeOutcome) -> Void)
    /// Whether an arrangement's original frames are held for a restore.
    var canRestoreArrangement: Bool { get }
    /// Put back the arranged windows that still stand where the layout
    /// left them. Answered on the main thread with how many were.
    func restoreArrangement(completion: @escaping (Int) -> Void)
}

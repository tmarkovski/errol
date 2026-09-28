// The hop every observation bridge in the shell re-arms through. Its own
// file because more than one controller tracks the model this way: the
// menu-bar shell (MenuBarController) and the transcript's window
// (TranscriptPanelController).

import Foundation

/// Carries a main-thread callback into withObservationTracking's @Sendable
/// onChange without capturing the (non-Sendable) shell there. Unchecked is
/// sound because the work both closes over and executes on the main queue.
struct MainQueueHop: @unchecked Sendable {
    private let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
    func run() { DispatchQueue.main.async(execute: work) }
}

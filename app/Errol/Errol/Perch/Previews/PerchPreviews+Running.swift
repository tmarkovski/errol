// The console during a run, paused and held included. The run plays on
// PerchPreviewEngine, so Stop and Pause to steer work in the canvas.

#if DEBUG
import SwiftUI

#Preview("Running · first reply") { PerchPreviewState.opening.scene }
#Preview("Running · mid-run") { PerchPreviewState.running.scene }
#Preview("Running · until you stop it") { PerchPreviewState.runningUntilStopped.scene }
#Preview("Running · model unavailable") { PerchPreviewState.modelUnavailable.scene }
#Preview("Running · pause pending") { PerchPreviewState.pausePending.scene }
#Preview("Running · paused, writing a note") { PerchPreviewState.paused.scene }
#Preview("Running · note queued") { PerchPreviewState.noteQueued.scene }
#Preview("Running · waiting for focus") { PerchPreviewState.waitingForFocus.scene }
#Preview("Running · Claude's conversation covered") { PerchPreviewState.conversationCovered.scene }
#Preview("Running · Claude minimized") { PerchPreviewState.held.scene }
#Preview("Running · handoffs, animated") { PerchPreviewState.handoffs.scene }
#Preview("Dark · mid-run") { PerchPreviewState.running.scene.preferredColorScheme(.dark) }
#Preview("Dark · paused, writing a note") { PerchPreviewState.paused.scene.preferredColorScheme(.dark) }
#endif

// The console once a run is over, one canvas per way it can end.

#if DEBUG
import SwiftUI

#Preview("Finished · complete") { PerchPreviewState.complete.scene }
#Preview("Finished · stopped") { PerchPreviewState.stopped.scene }
#Preview("Finished · turn limit reached") { PerchPreviewState.turnLimitReached.scene }
#Preview("Finished · delivery interrupted") { PerchPreviewState.interrupted.scene }
#Preview("Finished · note not sent") { PerchPreviewState.noteNotSent.scene }
#Preview("Dark · complete") { PerchPreviewState.complete.scene.preferredColorScheme(.dark) }
#endif

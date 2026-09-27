// The Update button beside the ··· menu, in each phase, on stand-in update
// statuses (UpdateStatus.preview) over the console's own states. A click
// on Update walks the stand-in on: it downloads for a moment, then offers
// the restart, which runs for a moment and comes back.

#if DEBUG
import SwiftUI

#Preview("Update · available") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.available(version: "1.0.3")))
}
#Preview("Update · ready to restart") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.ready(version: "1.0.3")))
}
#Preview("Update · updating") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.preparing(version: "1.0.3")))
}
#Preview("Update · restarting") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.restarting))
}
#Preview("Update · checking") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.checking))
}
#Preview("Update · up to date") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.idle, note: .upToDate))
}
#Preview("Update · couldn't update") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.idle, note: .problem(
            "The update couldn\u{2019}t be downloaded because the network connection was lost.")))
}
#Preview("Update · narrow console") {
    PerchPreviewState.narrow.scene
        .environment(\.updateStatus, .preview(.ready(version: "1.0.3")))
}
#Preview("Update · hidden mid-run") {
    PerchPreviewState.running.scene
        .environment(\.updateStatus, .preview(.ready(version: "1.0.3")))
}
#Preview("Update · after a run") {
    PerchPreviewState.complete.scene
        .environment(\.updateStatus, .preview(.ready(version: "1.0.3")))
}
#Preview("Dark · update available") {
    PerchPreviewState.bothConnected.scene
        .environment(\.updateStatus, .preview(.ready(version: "1.0.3")))
        .preferredColorScheme(.dark)
}
#endif

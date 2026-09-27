// The console before a run, one canvas per state. The scene, the states,
// and the preview engine they run on are in PerchPreviews.swift.

#if DEBUG
import SwiftUI

#Preview("Compose · several windows") { PerchPreviewState.severalWindows.scene }
#Preview("Compose · both connected") { PerchPreviewState.bothConnected.scene }
#Preview("Compose · no topic yet") { PerchPreviewState.noTopic.scene }
#Preview("Compose · Code session") { PerchPreviewState.codeSession.scene }
#Preview("Compose · Claude still replying") { PerchPreviewState.stillReplying.scene }
#Preview("Compose · ChatGPT closed") { PerchPreviewState.chatgptClosed.scene }
#Preview("Compose · Claude not installed") { PerchPreviewState.claudeNotInstalled.scene }
#Preview("Compose · long topic") { PerchPreviewState.longTopic.scene }
#Preview("Compose · ends after a set number of turns") { PerchPreviewState.turnLimit.scene }
#Preview("Compose · ends when you stop it") { PerchPreviewState.untilStopped.scene }
#Preview("Compose · narrow console") { PerchPreviewState.narrow.scene }
#Preview("Dark · both connected") { PerchPreviewState.bothConnected.scene.preferredColorScheme(.dark) }
#endif

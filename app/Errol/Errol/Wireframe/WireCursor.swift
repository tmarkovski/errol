// The pointing-hand cursor that anything clickable on the panel wears.

import AppKit
import SwiftUI

/// The pointing-hand cursor over a control, but only while the control does
/// something. Tracks its own push so a view that never pushed never pops
/// somebody else's cursor off the stack.
struct WireHandCursor: ViewModifier {
    var active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, active, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            // A panel that closes under the cursor never gets its hover exit.
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

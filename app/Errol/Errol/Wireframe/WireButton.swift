// The skin's boxed control, and the pointing-hand cursor that anything
// clickable on the panel wears.

import AppKit
import SwiftUI

/// The skin's boxed control, shared by the action row, the steering
/// editor, and the compact footer.
struct WireButton: View {
    var label: String
    var disabled: Bool
    /// Return triggers the control (the RUN button).
    var isDefault = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Wire.mono(9, .bold))
                .foregroundColor(disabled ? Wire.faint : Wire.ink)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(3))
                .overlay(Rectangle().stroke(disabled ? Wire.faint : Wire.ink,
                                            lineWidth: Wire.s(1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
    }
}

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

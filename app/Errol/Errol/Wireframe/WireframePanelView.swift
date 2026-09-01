// The wireframe instrument skin (see PanelRootView for skin selection):
// DesignMockups' Option A made real. The study's rule carries over as the
// design itself — every state is legible from lamps, needles, counters,
// and labels alone; four grays, no glow, no chassis color. The exceptions
// are the two signal lamps in the old machine-panel idiom — the readiness
// lamp burning red, amber, or green, and THINK an orange bulb breathing
// while a side composes; everything they say is still said in words on the
// nameplate below them, so the rule holds. The working side's card keeps
// the palette and spends motion instead: its border is played like a
// speaker, thumping and throwing rings on an irregular beat, and the gauge
// above it is knocked about its reading by those same hits, so the busy
// actor is the one thing on the panel that moves. The panel window is
// titled but draws none of its own chrome (MenuBarController), so the paper
// card this view paints fills it edge to edge: the card paints its own
// corner and the window casts the shadow from it, and AppKit's close button
// stands directly on the paper at the top-left — the title bar's strip is
// deliberately unpainted, so nothing marks where the window's chrome ends
// and the instrument begins (Wire.chromeBand is the room it gets).
//
// Idle, the full console shows the instrument head, the conversation
// setup, and the run options; the run log stays in memory and reads
// through the status item's debug window (WireLogWell). Starting a run
// shrinks the panel to the head unit alone. The card is content-sized in
// every state: it reports each laid-out size through onCardResize and the
// shell fits the window to it (MenuBarController.fitPanel). EXPAND brings
// the full console back mid-run with the setup rows disabled.
//
// The skin is split into child views along update boundaries, not visual
// ones: the controller is Observable, so each struct re-renders only for
// the properties its own body read. The editor sits in its own scope so a
// keystroke never touches the instruments. Extracted computed properties
// would not do this — only a child struct starts a new observation scope.
//
// The skin lives in this folder, one file per part. WireStyle has the
// palette and the window sizes; this file has the shell that stacks the
// rows. The rows are WireInstrumentHead, WireConversationSetup,
// WireRunControls, and WireSteeringEditor, with WireChrome
// putting the state word and the gear in the window's own title strip. The instruments
// those rows are built from — the courier, the gauge and odometer, the
// lamps, the speaker border, the button — each have their own file, named
// for the part, and so does the one thing that is not drawn at all: the
// beat two of those instruments play to (WireRhythm). A part more than one
// file builds on had to give up its private marker to move out here, and
// the Wire prefix stands in for what that marker was doing; a part only
// its own file builds on — the lamp face behind the signal lamps, the
// needle and the face behind the gauge, the digit wheel behind the
// odometer — still has it.

import SwiftUI

/// The shell: structure only. It reads the two properties that decide
/// which children mount (compact, isSteering); everything else is read
/// inside the child views, which is what keeps their invalidation apart.
struct WireframePanelView: View {
    let controller: RelayController
    /// The content-sized card reports each laid-out size here so the shell
    /// can fit the window to it (MenuBarController.fitPanel).
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        VStack(spacing: Wire.s(12)) {
            WireInstrumentHead(controller: controller)
            if controller.compact {
                WireCompactFooter(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
            } else {
                WireConversationSetup(controller: controller)
                WireActionControls(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
            }
        }
        .padding(.horizontal, Wire.s(16))
        .padding(.bottom, Wire.s(16))
        // The top clears the title band and the window strip behind it.
        .padding(.top, Wire.chromeInset)
        .frame(width: Wire.cardWidth)
        .background(
            // Edge to edge: the card is the window. The corner is painted
            // rather than left to AppKit — a window with a clear background
            // has no theme frame to round it — and the shadow around it is
            // the window's own, cast from this shape.
            RoundedRectangle(cornerRadius: Wire.shellCorner).fill(Wire.paper)
                // Bare paper — the card's padding and the gaps between
                // rows — moves the window, asked for outright rather than
                // through `isMovableByWindowBackground`, which only moves a
                // window when AppKit judges that nothing in the content
                // wanted the click — an inference that does not hold on
                // every macOS release. Text selection in the log and the
                // instruction editor is untouched: the gesture lives on the
                // paper, not over those.
                .gesture(WindowDragGesture())
        )
        .overlay(RoundedRectangle(cornerRadius: Wire.shellCorner).stroke(Wire.ink.opacity(0.3)))
        // The wordmark, set in the title bar's strip the way a window title
        // is — centered, clear of the close button leading and of the state
        // word and gear trailing (toolbar items, WireChrome). A centered
        // label needs no item; it lets every event through to the bar.
        .overlay(alignment: .top) {
            Text("ERROL")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
                .frame(height: Wire.chromeBand)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
        // Measured here — the card with its paddings, before the flexible
        // outer frame stretches to whatever window AppKit currently has —
        // so the size reported is the one the window should become.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onCardResize?(size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The title bar registers as a top safe-area inset, and the hosting
        // view honors it — laying the whole card out below the bar, with the
        // close button floating above the paper in an empty strip. Running
        // under the title bar is the point (the band is painted for the
        // button to stand in), so the inset is declined.
        .ignoresSafeArea()
    }
}

// The Perch skin (see PanelRootView for skin selection): the skin studies'
// clean-modern direction carrying the converged composer. Native macOS
// surfaces — system type, sentence case, soft warm neutrals — with one
// owl-amber accent shared by the primary button and the courier bead, and
// the playfulness spent on motion: the bead hops the flight path on every
// handoff. The two sides are perches — avatars with presence dots — and a
// quiet turn line replaces the wireframe's instrument cluster.
//
// The console is two rows in every state: the head (PerchHead) and the
// composer (PerchComposer), whose setup zone — quick shape pills and the
// instruction preview above a hairline — folds into a context row while a
// run is on. The window chrome follows the wireframe pattern exactly
// (MenuBarController.buildPanel): a titled panel that draws none of its
// chrome, the card content-sized and reported through onCardResize, and
// the title strip carrying the state pill and the session overflow as real
// toolbar items (PerchChrome).

import SwiftUI

/// The shell: structure only. The same two children mount in every state —
/// the properties that vary are read inside them, which is what keeps
/// their invalidation apart.
struct PerchPanelView: View {
    let controller: RelayController
    /// The content-sized card reports each laid-out size here so the shell
    /// can fit the window to it (MenuBarController.fitPanel).
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        VStack(spacing: Perch.s(14)) {
            PerchHead(controller: controller)
            PerchComposer(controller: controller)
        }
        .padding(.horizontal, Perch.s(18))
        .padding(.bottom, Perch.s(18))
        // The top clears the title band and the window strip behind it.
        .padding(.top, Perch.chromeInset)
        .frame(width: Perch.cardWidth)
        .background(
            RoundedRectangle(cornerRadius: Perch.shellCorner).fill(Perch.paper)
                // Bare paper moves the window (see WireframePanelView for
                // why the gesture is asked for outright).
                .gesture(WindowDragGesture())
        )
        .overlay(RoundedRectangle(cornerRadius: Perch.shellCorner)
            .stroke(Perch.panelEdge, lineWidth: 1))
        // The wordmark, centered in the title strip like a window title —
        // sentence case, because this skin is an app, not an instrument.
        .overlay(alignment: .top) {
            Text("Errol")
                .font(Perch.text(13, .semibold))
                .foregroundColor(Perch.ink)
                .frame(height: Perch.chromeBand)
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
        // Running under the title bar is the point (the band is where the
        // close button stands), so the safe-area inset is declined.
        .ignoresSafeArea()
    }
}

// Perch, the console: the converged composer (docs/design-proposals/
// chat-composer/converged-composer.html) in a clean, native dress. Native
// macOS surfaces — system type, sentence case, soft warm neutrals — with one
// theme accent shared by the primary button and the courier bead, and
// the playfulness spent on motion: the bead hops the flight path on every
// handoff. The two sides are perches — the apps' own icons with presence
// dots — and a quiet turn line says what the panel is doing.
//
// The console is two rows in every state: the head (PerchHead) and the
// composer (PerchComposer), whose setup zone — quick shape pills and the
// instruction preview above a hairline — folds into a context row while a
// run is on. The window is a titled panel that draws none of its chrome
// (MenuBarController.buildPanel): the card is content-sized and reported
// through onCardResize, and the title strip carries the state pill and the
// session overflow as real toolbar items (PerchChrome).

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
        // The card reports its content height to the window. Taking the
        // window's proposed height here would feed an in-flight resize
        // back into the next measurement, especially when a run replaces
        // the prompt editor with the shorter steering controls.
        .fixedSize(horizontal: false, vertical: true)
        .tint(Perch.accent)
        .background(
            RoundedRectangle(cornerRadius: Perch.shellCorner).fill(Perch.paper)
                // Bare paper — the card's padding and the gaps between rows
                // — moves the window, asked for outright rather than through
                // `isMovableByWindowBackground`, which only moves a window
                // when AppKit judges that nothing in the content wanted the
                // click, an inference that does not hold on every macOS
                // release. Text selection in the editor is untouched: the
                // gesture lives on the paper, not over it.
                .gesture(WindowDragGesture())
        )
        .overlay(RoundedRectangle(cornerRadius: Perch.shellCorner)
            .stroke(Perch.panelEdge, lineWidth: 1))
        // The wordmark, centered in the title strip like a window title, in
        // sentence case as a window title is.
        .overlay(alignment: .top) {
            Text("Errol")
                .font(Perch.text(13, .semibold))
                .foregroundColor(Perch.ink)
                .frame(height: Perch.chromeBand)
                .allowsHitTesting(false)
        }
        // Measured here — the card with its paddings — so the size reported
        // is the one the window should become. Fitting the card to the
        // window it sits in, and running it up under the title bar, is the
        // shell's business (MenuBarController.buildPanel), which is what
        // lets a preview canvas show the card at its own size.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onCardResize?(size)
        }
    }
}

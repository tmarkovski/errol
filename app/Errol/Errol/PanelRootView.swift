// The skin layer: the floating panel hosts PanelRootView, which renders
// the compiled-in skin. Every skin drives the same RelayController, so
// swapping UIs for a testing round is a one-line change: point
// activePanelStyle at another case and rebuild. Deliberately not a
// runtime setting — a menu plus a persisted preference would drag window
// chrome, sizing, and state through every switch for no testing benefit.
//
// The window chrome follows the skin (MenuBarController.buildPanel):
// classic gets the original titled utility panel; glass gets a borderless
// transparent panel, so Liquid Glass can sample the desktop behind it;
// wireframe gets a titled one that draws none of its chrome, so the paper
// instrument card fills the window and the real close button sits on it.

import SwiftUI

/// The compiled-in panel skin. Edit this line to swap UIs.
let activePanelStyle = PanelStyle.wireframe

enum PanelStyle {
    case glass
    case classic
    case wireframe
}

/// The one place panel frame sizes live. For the glass skin the AppKit
/// shell animates the window between these as the presentation state
/// changes; the classic skin has one fixed size.
enum PanelLayout {
    static func size(style: PanelStyle, compact: Bool, logOpen: Bool,
                     steering: Bool, fullPrompt: Bool) -> CGSize {
        switch style {
        case .classic:
            CGSize(width: 440, height: 620)
        case .glass:
            if compact {
                CGSize(width: 430, height: 160)
            } else {
                CGSize(width: 560,
                       height: logOpen ? (fullPrompt ? 760 : 660)
                                       : (fullPrompt ? 570 : 470))
            }
        case .wireframe:
            // Only the opening size. The wireframe card is content-sized
            // and reports its real size as it lays out; the shell fits the
            // window to that (MenuBarController.fitPanel), so no layout
            // table exists for this skin.
            WireframeMetrics.initialPanel
        }
    }
}

struct PanelRootView: View {
    let controller: RelayController
    /// Wireframe only: the content-sized card reports its size here so the
    /// shell can fit the window to it. The other skins size through
    /// PanelLayout and never call it.
    var onWireframeCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        switch activePanelStyle {
        case .glass:
            GlassPanelView(controller: controller)
        case .classic:
            ControlPanelView(controller: controller)
        case .wireframe:
            WireframePanelView(controller: controller,
                               onCardResize: onWireframeCardResize)
        }
    }
}

// The skin layer: the floating panel hosts PanelRootView, which renders
// the compiled-in skin. Every skin drives the same RelayController, so
// swapping UIs for a testing round is a one-line change: point
// activePanelStyle at another case and rebuild. Deliberately not a
// runtime setting — a menu plus a persisted preference would drag window
// chrome, sizing, and state through every switch for no testing benefit.
//
// The window chrome follows the skin (MenuBarController.buildPanel):
// classic gets the original titled utility panel; glass and wireframe get
// a borderless transparent panel — glass so Liquid Glass can sample the
// desktop behind it, wireframe so the paper instrument card it paints is
// the panel's own edge.

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
                     steering: Bool) -> CGSize {
        switch style {
        case .classic:
            CGSize(width: 440, height: 620)
        case .glass:
            if compact {
                CGSize(width: 430, height: 160)
            } else {
                CGSize(width: 560, height: logOpen ? 660 : 470)
            }
        case .wireframe:
            // Derived from the card the skin draws (WireframeMetrics), so
            // rescaling the instrument moves the window with it. The head
            // unit grows a row while the steering editor is open; expanded,
            // the fixed card lends the editor the log's room instead.
            compact ? (steering ? WireframeMetrics.compactSteeringPanel
                                : WireframeMetrics.compactPanel)
                    : WireframeMetrics.expandedPanel
        }
    }
}

struct PanelRootView: View {
    @ObservedObject var controller: RelayController

    var body: some View {
        switch activePanelStyle {
        case .glass:
            GlassPanelView(controller: controller)
        case .classic:
            ControlPanelView(controller: controller)
        case .wireframe:
            WireframePanelView(controller: controller)
        }
    }
}

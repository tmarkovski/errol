// The wireframe instrument skin (see PanelRootView for skin selection):
// DesignMockups' Option A made real. The study's rule carries over as the
// design itself — every state is legible from lamps, needles, counters,
// and labels alone; four grays, no glow, no chassis color. The exceptions
// are the two signal lamps in the old machine-panel idiom — the readiness
// lamp burning red, amber, or green, and THINK an orange bulb breathing
// while a side composes; everything they say is still said in words on the
// nameplate below them, so the rule holds. The working side's card keeps
// the palette and spends motion instead: its border is played like a
// speaker, thumping and throwing rings on an irregular beat, so the busy
// actor is the one thing on the panel that moves. The panel window is
// borderless (MenuBarController), so the paper card this view paints is
// the panel's own edge.
//
// Idle, the full console shows the instrument head, the conversation
// setup, run options, and the log. Starting a run shrinks the panel to
// the head unit alone (controller.compact drives the AppKit frame change;
// PanelLayout has the sizes). EXPAND brings the full console back mid-run
// with the setup rows disabled.
//
// The skin is split into child views along update boundaries, not visual
// ones: the controller is Observable, so each struct re-renders only for
// the properties its own body read. The editor sits in its own scope so a
// keystroke never touches the instruments, and the log well owns the one
// list that grows. Extracted computed properties would not do this — only
// a child struct starts a new observation scope.
//
// The skin lives in this folder, one file per part. WireStyle has the
// palette and the window sizes; this file has the shell that stacks the
// rows. The rows are WireHeader, WireInstrumentHead, WireConversationSetup,
// WireRunControls, WireSteeringEditor, and WireLogWell. The instruments
// those rows are built from — the courier, the gauge and odometer, the
// lamps, the speaker border, the button — each have their own file, named
// for the part. A part more than one file builds on had to give up its
// private marker to move out here, and the Wire prefix stands in for what
// that marker was doing; a part only its own file builds on — the lamp
// face behind the signal lamps, the beat track behind the speaker border,
// the digit wheel behind the odometer — still has it.

import SwiftUI

/// The shell: structure only. It reads the two properties that decide
/// which children mount (compact, isSteering); everything else is read
/// inside the child views, which is what keeps their invalidation apart.
struct WireframePanelView: View {
    let controller: RelayController

    var body: some View {
        VStack(spacing: Wire.s(12)) {
            WireHeader(controller: controller)
            WireInstrumentHead(controller: controller)
            if controller.compact {
                WireCompactFooter(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
            } else {
                WireConversationSetup(controller: controller)
                WireActionControls(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
                WireLogWell(controller: controller)
            }
        }
        .padding(Wire.s(16))
        .frame(width: Wire.cardWidth,
               height: controller.compact ? nil : Wire.expandedCardHeight)
        .background(
            RoundedRectangle(cornerRadius: Wire.shellCorner).fill(Wire.paper)
                .shadow(color: .black.opacity(0.28), radius: Wire.s(9), y: Wire.s(4))
                // Bare paper — the card's padding and the gaps between rows
                // — moves the window. See WireHeader for why the card asks
                // for the drag instead of leaving it to the window
                // background.
                .gesture(WindowDragGesture())
        )
        .overlay(RoundedRectangle(cornerRadius: Wire.shellCorner).stroke(Wire.ink.opacity(0.3)))
        .environment(\.colorScheme, .light)
        .padding(Wire.cardMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

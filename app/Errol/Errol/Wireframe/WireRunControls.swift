// The run controls in their two forms: the full console's button row, and
// the compact panel's footer, which carries the loaded shape and topic
// alongside a shorter set of the same buttons. One file because the two
// share their wording — a button that says PAUSE in both places should not
// be able to explain itself differently. See WireframePanelView for the skin.

import SwiftUI

/// Inspect/Run/Stop/Compact/Steer/Pause. Updates while the prompt is
/// typed — Run eligibility reads it — which is a small, deliberate
/// invalidation.
struct WireActionControls: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Wire.s(8)) {
            WireButton(label: "INSPECT", disabled: controller.isRunning) {
                controller.runInspect()
            }
            .help("Dump both apps' windows, buttons, and selector matches into the log")
            Spacer()
            if controller.isRunning {
                WireButton(label: "COMPACT", disabled: false) { controller.compact = true }
                    .help("Shrink to the head unit")
                WireButton(label: "STEER", disabled: controller.isSteering) {
                    controller.beginSteer()
                }
                .help(wireSteerHelp)
                WireButton(label: controller.isPaused ? "RESUME" : "PAUSE",
                           disabled: false) {
                    controller.togglePause()
                }
                .help(wirePauseHelp(isPaused: controller.isPaused,
                                    isHolding: controller.isHolding))
            }
            WireButton(label: "RUN",
                       disabled: controller.isRunning || !controller.instructionsReady,
                       isDefault: true) {
                controller.start()
            }
            WireButton(label: "STOP", disabled: !controller.isRunning) { controller.stop() }
        }
    }
}

/// The head unit's bottom row: the loaded shape and topic on the left,
/// the run controls on the right.
struct WireCompactFooter: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Wire.s(8)) {
            Text("[ \(controller.conversation.uppercased()) ]")
                .font(Wire.mono(9, .bold))
                .foregroundColor(Wire.ink)
            Text(topicSummary)
                .font(Wire.text(10))
                .foregroundColor(Wire.faint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Wire.s(8))
            WireButton(label: "STEER", disabled: controller.isSteering) {
                controller.beginSteer()
            }
            .help(wireSteerHelp)
            WireButton(label: controller.isPaused ? "RESUME" : "PAUSE", disabled: false) {
                controller.togglePause()
            }
            .help(wirePauseHelp(isPaused: controller.isPaused,
                                isHolding: controller.isHolding))
            WireButton(label: "STOP", disabled: false) { controller.stop() }
            WireButton(label: "EXPAND", disabled: false) { controller.compact = false }
                .help("Expand the full console")
        }
    }

    private var topicSummary: String {
        if controller.selectedTemplate == nil {
            return controller.customInstructions
                .components(separatedBy: .newlines).first ?? ""
        }
        return controller.topic
    }
}

// MARK: Shared tooltips

/// Pause/Steer wording shared by the action row and the compact footer.
private func wirePauseHelp(isPaused: Bool, isHolding: Bool) -> String {
    guard isPaused else { return "Hold the run at the next handoff" }
    return isHolding
        ? "Send the held reply and continue"
        : "Call off the pause and let the run carry on"
}

private let wireSteerHelp = "Hold the run and write a steering note into the conversation"

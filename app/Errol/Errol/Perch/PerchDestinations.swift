// The destination line under the prompt box, one side's window at each end.
// Its own file because it stands in the middle column, apart from the icons at the ends.

import SwiftUI

/// Each side's destination under the box: the window's mode, then its
/// model with the effort a shade lighter, and a problem when there is one.
/// It reads as a status, with no chevron. Where there is something to do,
/// it is a chip that does it: it lists the app's windows to choose from
/// when there are several, opens the app while it is closed, or brings it
/// forward to open a conversation. Through a run it is a plain label. It
/// hugs its text, so only the text is the target, and a new destination
/// springs it to its new width.
struct PerchDestinations: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lines = Speaker.allCases.map { ParticipantPresentation(controller: controller, speaker: $0) }
        HStack(spacing: Perch.s(12)) {
            destination(lines[0]).frame(maxWidth: .infinity, alignment: .leading)
            destination(lines[1]).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(reduceMotion ? nil : Perch.spring,
                   value: lines.map { [$0.side.destinationSurface ?? "", $0.destination, $0.problem ?? ""] })
        .padding(.horizontal, PerchMetrics.promptTextInset - PerchChip.inset)
        .frame(height: Perch.s(17))
    }

    private func destination(_ info: ParticipantPresentation) -> some View {
        Group {
            switch info.lineAction {
            case .choose:
                Menu { windows(info) } label: { text(info).perchChip() }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
            case .open:
                Button { controller.setup.launch(info.speaker) } label: { text(info).perchChip() }
                    .buttonStyle(.plain)
            case .focus:
                Button { controller.showWindow(info.speaker) } label: { text(info).perchChip() }
                    .buttonStyle(.plain)
            case nil:
                text(info)
                    .padding(.horizontal, PerchChip.inset)
                    .frame(height: PerchChip.height)
            }
        }
        .accessibilityLabel("\(info.name): \(info.destination)")
        .accessibilityValue(info.stateText)
        .accessibilityHint(info.lineAction?.hint(name: info.name) ?? "")
    }

    private func text(_ info: ParticipantPresentation) -> some View {
        // Nothing connected yet: the line is what to do, in the accent. A
        // connection not checked since the last run stays muted.
        let needsSomething = !info.side.isConnected && info.state == .attention && !info.isRemembered
        let surface = info.side.destinationSurface
        let model = info.modelAndEffort
        return HStack(spacing: Perch.s(4)) {
            if let surface {
                Text(surface).fontWeight(.medium).fixedSize()
            }
            if let model {
                if surface != nil { Text("\u{00B7}").foregroundStyle(Perch.muted).fixedSize() }
                // The effort follows the model a shade lighter, as the apps
                // set it apart in their own model buttons.
                let effort = Text(model.effort.map { " \($0)" } ?? "").foregroundStyle(Perch.muted)
                Text("\(model.model)\(effort)").truncationMode(.tail)
            }
            if surface == nil, model == nil {
                Text(info.destination).truncationMode(.middle)
                    .foregroundStyle(needsSomething ? Perch.accentText : info.isRemembered ? Perch.muted : Perch.secondary)
            }
            if let problem = info.problem {
                Text("\u{00B7} \(problem)").fontWeight(.medium).foregroundStyle(Perch.red).fixedSize()
            }
        }
        .font(Perch.text(11.5)).lineLimit(1)
        .foregroundStyle(info.isRemembered ? Perch.muted : Perch.secondary)
    }

    /// The app's windows, front first, the connected one checked.
    private func windows(_ info: ParticipantPresentation) -> some View {
        ForEach(info.side.windowChoices) { choice in
            Toggle("\(choice.label) \u{00B7} \(choice.candidate.stateLine)", isOn: Binding(
                get: { info.side.connection?.window == choice.id },
                set: { if $0 { controller.connect(info.speaker, to: choice.id) } }))
        }
    }
}

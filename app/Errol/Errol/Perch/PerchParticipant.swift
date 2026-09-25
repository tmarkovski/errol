// App identity at the ends; destination details use the wider line below the box.
//
// Each end is the app's icon with a state badge straddling its lower trailing
// corner, and the app's name under it. The icon and the side's destination
// line both open the side's details (PerchParticipantPopover), and close them
// again when they are open.
import AppKit
import SwiftUI

struct PerchParticipant: View {
    @Bindable var controller: RelayController
    let speaker: Speaker
    @State private var hovering = false

    var body: some View {
        let presentation = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(spacing: Perch.s(6)) {
            Button { controller.toggleDetails(speaker) } label: {
                PerchAvatar(bundleID: presentation.bundleID,
                            initial: String(presentation.name.prefix(1)), feather: presentation.feather)
                    .opacity(presentation.state == .waiting ? 0.8 : 1)
                    .animation(Perch.fade, value: presentation.state)
                    // The icon answers the pointer the way a Dock icon does:
                    // it darkens a little. The badge keeps its color.
                    .brightness(hovering ? -0.06 : 0)
                    // A little shadow lifts the icon off the shell, as the
                    // prompt box's lifts the box. The badge is cut out of
                    // the artwork, so it takes none of its own.
                    .shadow(color: Perch.shadow, radius: Perch.s(2), y: Perch.s(1))
                    .overlay(alignment: .bottomTrailing) {
                        ParticipantBadge(state: presentation.state)
                            .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] + ParticipantBadge.cornerInset }
                            .alignmentGuide(.bottom) { $0[VerticalAlignment.center] + ParticipantBadge.cornerInset }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onKeyPress(.return) {
                controller.toggleDetails(speaker)
                return .handled
            }
            .accessibilityLabel("\(presentation.name) participant details")
            .accessibilityValue(presentation.stateText)
            .help(presentation.details)
            .background {
                if let source = controller.iconTransferSources[speaker] {
                    PromptTransferProbe(source: source).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background {
                PerchDetailsAnchor(isPresented: Binding(
                    get: { controller.presentedParticipant == speaker },
                    set: { if !$0 && controller.presentedParticipant == speaker { controller.presentedParticipant = nil } }),
                    canTakeFocus: { controller.consoleAccess.canTakeFocus }) {
                    PerchParticipantPopover(controller: controller, speaker: speaker)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Text(presentation.name).font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .lineLimit(1).frame(height: Perch.s(17))
        }
        .frame(width: Perch.participantWidth)
    }
}

extension RelayController {
    /// The icon and the destination line both open a side's details, and
    /// close them when they are already open.
    func toggleDetails(_ speaker: Speaker) {
        presentedParticipant = presentedParticipant == speaker ? nil : speaker
    }
}

enum ParticipantState {
    case ready, attention, replying, waiting

    /// Every state is a filled circle with a white mark in it, so the four
    /// share a silhouette on the icon and differ in their mark and color.
    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .replying: "ellipsis.circle.fill"
        case .waiting: "clock.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .ready: "Ready"
        case .attention: "Needs attention"
        case .replying: "Replying"
        case .waiting: "Waiting"
        }
    }

    /// Status colors are the system's, adapting to the appearance and to
    /// Increase Contrast; replying is Errol's own activity, so it takes the
    /// theme's accent.
    var color: Color {
        switch self {
        case .ready: Color(nsColor: .systemGreen)
        case .attention: Color(nsColor: .systemOrange)
        case .replying: Perch.accent
        case .waiting: Color(nsColor: .systemGray)
        }
    }

    /// The mark on that color: white on the system's, and on the accent the
    /// theme's own ink for it, which a dark theme's light accent needs.
    var mark: Color { self == .replying ? Perch.onAccent : .white }
}

/// A state as a badge: the state's mark on its color, ringed in the
/// window's shell where it sits over an icon, so it reads as cut out of the
/// artwork. A new state replaces the mark in place.
struct ParticipantBadge: View {
    let state: ParticipantState
    var size = Perch.s(12)
    var ringed = true

    /// How far in from the icon frame's corner the badge's center sits: on
    /// the squircle's rounded corner, so the badge straddles the icon's edge
    /// instead of sitting inside the artwork.
    static let cornerInset = Perch.s(3.5)

    var body: some View {
        Image(systemName: state.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(state.mark, state.color)
            .font(.system(size: size, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .background {
                if ringed { Circle().fill(Perch.shell).padding(-Perch.s(0.5)) }
            }
            .animation(Perch.fade, value: state)
            .accessibilityLabel(state.title)
    }
}

/// Read current window metadata, falling back to the binding only if no sweep
/// has seen that window. A remembered hint is explicitly unverified.
struct ParticipantPresentation {
    let controller: RelayController
    let speaker: Speaker
    var side: SideSetup { controller.setup.state[speaker] }
    var name: String { controller.appName(speaker) }
    var bundleID: String { speaker == .chatgpt ? config.chatgptBundleID : config.claudeBundleID }
    var feather: Color { speaker == .chatgpt ? Perch.chatgptFeather : Perch.claudeFeather }
    var conversation: ConversationStatus {
        speaker == .chatgpt ? controller.chatgptConversation : controller.claudeConversation
    }
    var shortStatus: String? {
        if let block = controller.block, block.side == speaker { return block.shortStatus }
        if controller.stage == .finished, let outcome = controller.lastReport?.outcome,
           outcome.attentionSide == speaker { return outcome.shortStatus }
        return side.connection?.readiness.shortStatus
    }
    var state: ParticipantState {
        if controller.block?.side == speaker || (controller.stage == .finished && controller.lastReport?.outcome.attentionSide == speaker) {
            return .attention
        }
        if controller.isRunning {
            return conversation == .chatting ? .replying : .waiting
        }
        if side.isReady { return .ready }
        if side.presence == .checking || side.presence == .launching || side.connection?.readiness == .unverified { return .waiting }
        return .attention
    }
    var stateText: String {
        if controller.isRunning { return controller.consoleAccess.pauseGranted ? "Paused" : shortStatus ?? state.title }
        return shortStatus ?? (side.isConnected ? state.title : presenceText)
    }
    /// What a side with nothing connected is, in the words its badge stands
    /// for; the destination line says what to do about it.
    private var presenceText: String {
        switch side.presence {
        case .checking: "Checking\u{2026}"
        case .notInstalled: "Not installed"
        case .notRunning: "Not running"
        case .launching: "Opening\u{2026}"
        case .noWindow: "No window open"
        case .noConversation: "No conversation open"
        case .available: "Not connected"
        }
    }
    var needsChoice: Bool { !side.isConnected && !side.eligible.isEmpty }
    var isRemembered: Bool {
        side.connection?.readiness == .unverified || (!side.isConnected && !needsChoice && side.hint != nil)
    }
    var destination: String {
        if let title = side.destinationName {
            return side.connection?.readiness == .unverified ? "Last used · \(title)" : title
        }
        if needsChoice {
            return side.eligible.count == 1 ? "Choose this conversation" : "Choose one of \(side.eligible.count) conversations"
        }
        if let hint = side.hint { return "Last used · \(hint.name)" }
        if side.presence == .noWindow || side.presence == .noConversation { return "Open a conversation in \(name)" }
        return side.presence.action(name: name)
    }
    /// A problem the destination line names after the title, in red. "Last
    /// used" is not one; the muted title already says it.
    var problem: String? {
        guard let status = shortStatus, status != "Last used" else { return nil }
        return status
    }
    /// Whether the continuing conversation or a new one: said only when the
    /// window's title does not already say it.
    var continuation: String? {
        switch side.destinationContext {
        case "Continues here"?: "continues this chat"
        case "New chat"? where destination != "New chat": "starts a new chat"
        default: nil
        }
    }
    var details: String {
        [name, destination, side.destinationSurface, side.destinationModel, side.destinationContext, stateText]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Each side's destination under the box, as a chip: the surface, the
/// title truncated in the middle so similar titles keep the ends that tell
/// them apart, a problem when there is one, and the chevron that says it
/// opens the side's details. It hugs its text, so only the text is the
/// target, and a new destination springs the chip to its new width.
struct PerchDestinations: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lines = [Speaker.chatgpt, .claude].map { ParticipantPresentation(controller: controller, speaker: $0) }
        HStack(spacing: Perch.s(12)) {
            destination(lines[0]).frame(maxWidth: .infinity, alignment: .leading)
            destination(lines[1]).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(reduceMotion ? nil : Perch.spring,
                   value: lines.map { [$0.side.destinationSurface ?? "", $0.destination, $0.problem ?? ""] })
        .padding(.horizontal, PerchPromptBox.textInset - PerchChip.inset)
        .frame(height: Perch.s(17))
    }

    private func destination(_ info: ParticipantPresentation) -> some View {
        let speaker = info.speaker
        // Nothing connected yet: the line is what to do, in the accent. A
        // remembered destination stays muted, as unverified.
        let needsSomething = !info.side.isConnected && info.state == .attention && !info.isRemembered
        return Button { controller.toggleDetails(speaker) } label: {
            HStack(spacing: Perch.s(4)) {
                if let surface = info.side.destinationSurface {
                    Text(surface).fontWeight(.medium).fixedSize()
                    Text("\u{00B7}").foregroundStyle(Perch.muted).fixedSize()
                }
                Text(info.destination).truncationMode(.middle)
                    .foregroundStyle(needsSomething ? Perch.accentText : info.isRemembered ? Perch.muted : Perch.secondary)
                if let problem = info.problem {
                    Text("\u{00B7} \(problem)").fontWeight(.medium).foregroundStyle(Perch.red).fixedSize()
                }
                Image(systemName: "chevron.down").font(Perch.text(8, .semibold))
                    .foregroundStyle(needsSomething ? Perch.accentText : Perch.muted).fixedSize()
            }
            .font(Perch.text(11.5)).lineLimit(1)
            .foregroundStyle(Perch.secondary)
            .perchChip()
        }
        .buttonStyle(.plain)
        .background(PerchDetailsToggleRegion().allowsHitTesting(false).accessibilityHidden(true))
        .help(info.details)
        .onKeyPress(.return) {
            controller.toggleDetails(speaker)
            return .handled
        }
        .accessibilityLabel("\(info.name) destination: \(info.destination)")
        .accessibilityValue(info.stateText)
        .accessibilityHint("Opens participant details")
    }
}

/// A side's details, from its icon or its destination line: the app and its
/// state, the destination in full, what Errol does with the window, and the
/// actions the run allows now. An action the run holds back stays in place,
/// disabled, and the line under the actions says why. The card and its
/// arrow are PerchDetailsCallout's.
struct PerchParticipantPopover: View {
    let controller: RelayController
    let speaker: Speaker

    static let width = Perch.s(322)

    var body: some View {
        let info = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(alignment: .leading, spacing: Perch.s(12)) {
            header(info)
            VStack(alignment: .leading, spacing: Perch.s(3)) {
                Text(info.destination)
                    .font(Perch.text(12.5, .medium))
                    .foregroundStyle(info.isRemembered ? Perch.secondary : Perch.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let metadata = [info.side.destinationSurface, info.side.destinationModel, info.continuation]
                    .compactMap { $0 }.joined(separator: " \u{00B7} ")
                if !metadata.isEmpty {
                    Text(metadata).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Errol writes into this window, whatever conversation it shows when a message is due.")
                .font(Perch.text(11)).foregroundStyle(Perch.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Perch.s(8)) {
                // Side by side when both labels fit whole, else one above
                // the other; a label never truncates.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Perch.s(8)) { primaryAction(info); chooseMenu(info) }
                    VStack(alignment: .leading, spacing: Perch.s(8)) { primaryAction(info); chooseMenu(info) }
                }
                if let reason = reason(info) {
                    Text(reason).font(Perch.text(10.5)).foregroundStyle(Perch.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .animation(Perch.fade, value: reason(info))
        }
        .padding(Perch.s(14))
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(info.name) details")
        .accessibilityAction(.escape) { controller.presentedParticipant = nil }
    }

    private func header(_ info: ParticipantPresentation) -> some View {
        HStack(spacing: Perch.s(9)) {
            PerchAvatar(bundleID: info.bundleID, initial: String(info.name.prefix(1)), feather: info.feather)
                .scaleEffect(28.0 / 46.0)
                .frame(width: Perch.s(28), height: Perch.s(28))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Perch.s(1)) {
                Text(info.name).font(Perch.text(13, .semibold)).foregroundStyle(Perch.ink)
                HStack(spacing: Perch.s(4)) {
                    ParticipantBadge(state: info.state, size: Perch.s(10), ringed: false)
                        .accessibilityHidden(true)
                    Text(sentenceCase(info.stateText)).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                        .contentTransition(.opacity)
                }
                .animation(Perch.fade, value: info.stateText)
            }
        }
    }

    /// Open while the app is closed, and Show window once it is open.
    @ViewBuilder private func primaryAction(_ info: ParticipantPresentation) -> some View {
        switch info.side.presence {
        case .notRunning, .notInstalled, .launching:
            PerchCapsuleButton(title: info.side.presence == .launching ? "Opening\u{2026}" : "Open \(info.name)",
                               icon: "arrow.up.right") {
                guard !controller.isRunning else { return }
                controller.setup.launch(speaker)
            }
            .disabled(controller.isRunning || info.side.presence != .notRunning)
        default:
            PerchCapsuleButton(title: "Show window", style: .secondary, icon: "macwindow") {
                controller.presentedParticipant = nil
                controller.showWindow(speaker)
            }
            .disabled(!controller.consoleAccess.canShowWindow || !info.side.presence.isOpen)
        }
    }

    /// The app's eligible windows, the connected one checked.
    private func chooseMenu(_ info: ParticipantPresentation) -> some View {
        Menu {
            ForEach(info.side.eligible) { candidate in
                Toggle("\(candidate.name) \u{00B7} \(candidate.stateLine)", isOn: Binding(
                    get: { info.side.connection?.window == candidate.id },
                    set: {
                        guard $0 else { return }
                        controller.connect(speaker, to: candidate.id)
                        controller.presentedParticipant = nil
                    }))
            }
        } label: {
            PerchCapsuleLabel(title: info.side.isConnected ? "Choose another\u{2026}" : "Choose a conversation\u{2026}",
                              style: .secondary, icon: "arrow.left.arrow.right")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!controller.consoleAccess.canChangeDestination || info.side.eligible.isEmpty || controller.setup.isBinding)
    }

    private func reason(_ info: ParticipantPresentation) -> String? {
        if controller.isShowingWindow { return "Waiting for the window to appear\u{2026}" }
        if controller.isRunning {
            let later = info.side.isConnected ? "Choose another" : "Choose a conversation"
            return controller.consoleAccess.pauseGranted
                ? "\(later) once the run ends."
                : "Pause to show this window or to type in either conversation. \(later) once the run ends."
        }
        switch info.side.presence {
        case .notInstalled: return "Install \(info.name) to connect it."
        case .notRunning: return "Open \(info.name) to choose a conversation."
        case .checking, .launching: return nil
        default: break
        }
        if info.side.eligible.isEmpty { return "Open a conversation in \(info.name) first." }
        return controller.setup.problem
    }

    private func sentenceCase(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

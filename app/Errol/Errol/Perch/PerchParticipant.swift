// App identity at the ends; destination details use the wider line below the box.
//
// Each end is the app's icon with a state badge straddling its lower trailing
// corner, and the app's name under it. A click on the icon focuses the app,
// its connected window in front, or opens it when it is closed. Resting the
// pointer on the icon brings up its tip (PerchParticipantTip): what a click
// does, then the window's mode, model, effort, and state.
import AppKit
import SwiftUI

struct PerchParticipant: View {
    @Bindable var controller: RelayController
    let speaker: Speaker
    @State private var hovering = false
    /// The tip, once the pointer has rested on the icon a moment.
    @State private var tipShown = false
    @State private var tipDelay: Task<Void, Never>?
    /// A click puts the tip away until the pointer leaves the icon.
    @State private var tipSpent = false

    /// How long the pointer rests on the icon before its tip shows.
    static let tipWait = Duration.milliseconds(450)

    var body: some View {
        let presentation = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(spacing: Perch.s(6)) {
            Button { click(presentation.click) } label: {
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
            .onHover(perform: hover)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onKeyPress(.return) {
                click(presentation.click)
                return .handled
            }
            .accessibilityLabel(presentation.name)
            .accessibilityValue(presentation.spokenFacts)
            .accessibilityHint(presentation.click.hint(name: presentation.name))
            .background {
                if let source = controller.iconTransferSources[speaker] {
                    PromptTransferProbe(source: source).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background {
                PerchTipAnchor(isPresented: $tipShown) {
                    PerchParticipantTip(controller: controller, speaker: speaker)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Text(presentation.name).font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .lineLimit(1).frame(height: Perch.s(17))
        }
        .frame(width: Perch.participantWidth)
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        tipDelay?.cancel()
        guard inside else {
            tipShown = false
            tipSpent = false
            return
        }
        guard !tipSpent else { return }
        tipDelay = Task { @MainActor in
            try? await Task.sleep(for: Self.tipWait)
            if !Task.isCancelled { tipShown = true }
        }
    }

    private func click(_ click: ParticipantPresentation.Click) {
        tipDelay?.cancel()
        tipShown = false
        tipSpent = true
        switch click {
        case .focus: controller.showWindow(speaker, returningKeyboard: false)
        case .open: controller.setup.launch(speaker)
        case .unavailable: break
        }
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
    /// A connection not checked since the last run: the line stays muted
    /// until a sweep reads the window again.
    var isRemembered: Bool { side.connection?.readiness == .unverified }
    /// What the line under the box says. For a connected side, that is the
    /// window's mode, then its model with the effort after it, each only
    /// where the window shows one, since nothing about the conversation in
    /// it can be told reliably. Otherwise, what to do next, or what is
    /// happening.
    var destination: String {
        if side.isConnected {
            let model = modelAndEffort.map { [$0.model, $0.effort].compactMap { $0 }.joined(separator: " ") }
            let parts = [side.destinationSurface, model].compactMap { $0 }
            return parts.isEmpty ? "Connected" : parts.joined(separator: " \u{00B7} ")
        }
        if side.needsWindowChoice { return "Choose one of \(side.eligible.count) windows" }
        if side.presence == .noWindow || side.presence == .noConversation { return "Open a conversation in \(name)" }
        return side.presence.action(name: name)
    }
    /// A problem the destination line names after the window, in red.
    /// "Last used" is not one; the muted line already says it.
    var problem: String? {
        guard let status = shortStatus, status != "Last used" else { return nil }
        return status
    }

    /// What a click on the icon does now: bring the app forward, keyboard
    /// and all, or open it while it is closed. When it can do neither, the
    /// tip says why, where there is something to say.
    enum Click: Equatable {
        case focus, open
        case unavailable(String?)

        /// The tip's first line.
        var line: String? {
            switch self {
            case .focus: "Click to focus"
            case .open: "Click to open"
            case .unavailable(let reason): reason
            }
        }

        func hint(name: String) -> String {
            switch self {
            case .focus: "Brings \(name) forward"
            case .open: "Opens \(name)"
            case .unavailable(let reason): reason ?? ""
            }
        }
    }

    var click: Click {
        switch side.presence {
        case .notRunning: return controller.isRunning ? .unavailable("Open \(name) once the run ends") : .open
        case .notInstalled: return .unavailable("Install \(name) to use it")
        case .checking, .launching: return .unavailable(nil)
        case .noWindow, .noConversation, .available: break
        }
        if controller.consoleAccess.canShowWindow { return .focus }
        if controller.isShowingWindow { return .unavailable("Bringing \(name) forward\u{2026}") }
        if controller.stopRequested { return .unavailable("Focus once the run stops") }
        if controller.isSteeringPending { return .unavailable("Focus once the run pauses") }
        return .unavailable("Pause to focus")
    }

    /// The model the window shows, and its effort apart from it.
    var modelAndEffort: (model: String, effort: String?)? {
        guard let line = side.destinationModel else { return nil }
        return splitEffort(line, selectors: speaker == .chatgpt ? config.chatgptSelectors : config.claudeSelectors)
    }

    /// The tip's lines under what a click does, each only where the window
    /// has something to say.
    var facts: [ParticipantFact] {
        var facts: [ParticipantFact] = []
        if let surface = side.destinationSurface { facts.append(ParticipantFact(label: "Mode", value: surface)) }
        if let model = modelAndEffort {
            facts.append(ParticipantFact(label: "Model", value: model.model))
            if let effort = model.effort { facts.append(ParticipantFact(label: "Effort", value: effort)) }
        }
        facts.append(ParticipantFact(label: "Status", value: stateText.prefix(1).uppercased() + stateText.dropFirst(),
                                     badge: state))
        return facts
    }

    /// The facts as VoiceOver reads them on the icon, the state first.
    var spokenFacts: String {
        let facts = facts
        return (facts.suffix(1) + facts.dropLast()).map { "\($0.label) \($0.value)" }.joined(separator: ", ")
    }
}

/// One of a tip's lines: a label and its value. The status wears the
/// side's badge.
struct ParticipantFact: Identifiable {
    let label: String
    let value: String
    var badge: ParticipantState? = nil
    var id: String { label }
}

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
                Button { controller.showWindow(info.speaker, returningKeyboard: false) } label: { text(info).perchChip() }
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

extension ParticipantPresentation {
    /// What a click on the destination line does: choose among the app's
    /// windows, open the app, or bring it forward to open a conversation.
    enum LineAction {
        case choose, open, focus

        func hint(name: String) -> String {
            switch self {
            case .choose: "Chooses the window"
            case .open: "Opens \(name)"
            case .focus: "Brings \(name) forward"
            }
        }
    }

    /// nil leaves the line a plain label: through a run, while the app
    /// is being checked or opened, when it is not installed, and while it
    /// has only one window, which connects on its own.
    var lineAction: LineAction? {
        switch side.presence {
        case .notRunning: controller.isRunning ? nil : .open
        case .noWindow, .noConversation:
            !controller.isRunning && controller.consoleAccess.canShowWindow ? .focus : nil
        case .available:
            controller.consoleAccess.canChangeDestination && side.hasSeveralWindows ? .choose : nil
        case .checking, .notInstalled, .launching: nil
        }
    }
}

/// A side's tip, from its icon: what a click does, then what the side's
/// window is set to, one fact a line, the labels in a column of their own.
/// PerchTip draws it white on black.
struct PerchParticipantTip: View {
    let controller: RelayController
    let speaker: Speaker

    var body: some View {
        let info = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            if let line = info.click.line {
                let actionable = info.click == .focus || info.click == .open
                Text(line).font(Perch.text(12, .semibold))
                    .foregroundStyle(.white.opacity(actionable ? 1 : 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Perch.s(12), verticalSpacing: Perch.s(4)) {
                ForEach(info.facts) { fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(.white.opacity(0.55)).fixedSize()
                        value(fact)
                    }
                }
            }
            .font(Perch.text(11.5))
        }
    }

    private func value(_ fact: ParticipantFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(4)) {
            if let badge = fact.badge {
                ParticipantBadge(state: badge, size: Perch.s(10), ringed: false)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Perch.s(3.5) }
            }
            Text(fact.value).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .lineLimit(3)
    }
}

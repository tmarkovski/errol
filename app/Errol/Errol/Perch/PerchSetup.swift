// The guided setup inside the capsule: the meter over the center, the
// center's instruction for each step, the actions beside it, and the
// window picker with its keyboard. Screens 02–05 of the reference
// (docs/design-proposals/setup-interaction/SPEC.md); the participants'
// columns and the destination details are in PerchAvatar.swift.

import SwiftUI

// MARK: - Progress

/// Four short segments for the four steps: done in the success color, the
/// current one in the accent and a hair thicker, the rest on the track.
/// Color alone carries nothing: the meter speaks its step to VoiceOver.
struct PerchProgressMeter: View {
    let controller: RelayController

    var body: some View {
        let state = controller.setup.state
        HStack(spacing: Perch.s(5)) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                let progress = state.progress(of: step)
                Capsule()
                    .fill(color(progress))
                    .frame(height: progress == .current ? Perch.s(4) : Perch.s(3))
                    .frame(height: Perch.s(4))
                    .animation(Perch.fade, value: progress)
            }
        }
        .frame(maxWidth: Perch.s(220), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(state.progressDescription(names: controller.names))
    }

    private func color(_ progress: StepProgress) -> Color {
        switch progress {
        case .done: return Perch.green
        case .current: return Perch.accent
        case .remaining: return Perch.track
        }
    }
}

// MARK: - The center

/// The instruction for the current step, where the editor sits later.
struct PerchSetupCenter: View {
    let controller: RelayController

    private var setup: SetupController { controller.setup }
    private var names: (chatgpt: String, claude: String) { controller.names }

    var body: some View {
        switch setup.state.phase {
        case .prepareApps: prepare
        case .arrange: arrange
        case .connect(let side): connect(side)
        case .compose: EmptyView()
        }
    }

    // MARK: Prepare

    private var prepare: some View {
        let state = setup.state
        let waiting = [Speaker.chatgpt, .claude].first { !state[$0].presence.isAvailable }
        return copy(
            headline: prepareHeadline(state, waiting: waiting),
            supporting: waiting.flatMap { state[$0].presence.problem(name: name($0)) }
                ?? "Errol relays between the two desktop apps. Continue when both show a conversation.",
            problem: setup.problem)
    }

    private func prepareHeadline(_ state: SetupState, waiting: Speaker?) -> String {
        guard let waiting else { return "Both apps are ready" }
        let bothClosed = [Speaker.chatgpt, .claude].allSatisfy {
            state[$0].presence == .notRunning || state[$0].presence == .launching
        }
        switch state[waiting].presence {
        case .notRunning: return bothClosed ? "Open both apps" : "Open \(name(waiting))"
        case .launching: return "Opening \(name(waiting))\u{2026}"
        case .notInstalled: return "\(name(waiting)) isn't installed"
        case .noWindow, .noConversation: return "Open a conversation in \(name(waiting))"
        case .checking: return "Checking the apps\u{2026}"
        case .available: return "Both apps are ready"
        }
    }

    // MARK: Arrange

    private var arrange: some View {
        let state = setup.state
        return VStack(alignment: .leading, spacing: Perch.s(7)) {
            Text("Arrange the windows")
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(1)
            Picker("Layout", selection: Binding(get: { setup.state.layout }, set: { setup.choose($0) })) {
                ForEach(LayoutChoice.allCases, id: \.self) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: Perch.s(300), alignment: .leading)
            .accessibilityLabel("Window layout")
            supportingLine(arrangeSupporting(state), problem: setup.problem ?? state.layoutProblem)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func arrangeSupporting(_ state: SetupState) -> String {
        if let side = [Speaker.chatgpt, .claude].first(where: { state[$0].needsArrangementChoice }) {
            return "\(name(side)) has several windows: click its icon to choose the one to move."
        }
        if state.layoutApplied {
            return state.layout.movesWindows
                ? "Windows arranged. Continue when they look right."
                : "Positions kept. Continue when you're ready."
        }
        return "Both chat windows move so you can watch the exchange. They can go back later from the settings."
    }

    // MARK: Connect

    private func connect(_ side: Speaker) -> some View {
        Group {
            if let picker = setup.picker, picker.side == side {
                PerchWindowPickerList(controller: controller, picker: picker)
            } else {
                connectInstruction(side)
            }
        }
    }

    /// The instruction block, with the arrow at the edge nearest the icon
    /// it points at: leading and left-pointing for ChatGPT, trailing and
    /// right-pointing for Claude, whose block is right-aligned to match.
    private func connectInstruction(_ side: Speaker) -> some View {
        let leading = side == .chatgpt
        let state = setup.state
        return HStack(spacing: Perch.s(12)) {
            if leading { PerchArrowCue(pointsLeft: true) }
            VStack(alignment: leading ? .leading : .trailing, spacing: Perch.s(5)) {
                Text("Connect \(name(side)) to its conversation")
                    .font(Perch.text(19, .medium))
                    .foregroundStyle(Perch.ink)
                    .lineLimit(2)
                Text(controller.firstSpeaker == side
                     ? "Choose where your first message will go."
                     : "Choose where \(name(other(than: side)))'s replies will land.")
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.secondary)
                    .lineLimit(2)
                if let problem = setup.problem {
                    Text(problem)
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.red)
                        .lineLimit(2)
                } else if let hint = state[side].hint {
                    Text("Last used: \(hint.name)")
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Click \(name(side))'s icon, or press Return, to choose its window.")
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.muted)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(leading ? .leading : .trailing)
            if !leading { PerchArrowCue(pointsLeft: false) }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    // MARK: Furniture

    private func copy(headline: String, supporting: String, problem: String?) -> some View {
        VStack(alignment: .leading, spacing: Perch.s(5)) {
            Text(headline)
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(2)
                .contentTransition(.opacity)
            supportingLine(supporting, problem: problem)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Perch.fade, value: headline)
    }

    private func supportingLine(_ supporting: String, problem: String?) -> some View {
        Text(problem ?? supporting)
            .font(Perch.text(12))
            .foregroundStyle(problem == nil ? Perch.secondary : Perch.red)
            .lineLimit(2)
            .help(problem ?? supporting)
            .contentTransition(.opacity)
            .animation(Perch.fade, value: problem ?? supporting)
    }

    private func name(_ side: Speaker) -> String {
        side == .chatgpt ? names.chatgpt : names.claude
    }

    private func other(than side: Speaker) -> Speaker {
        side == .chatgpt ? .claude : .chatgpt
    }
}

// MARK: - The arrow

/// The cue that says what to pick up: an arrow beside the instruction,
/// nudging toward the icon three times, then still. About 7 points of
/// travel and 0.9 seconds per nudge, as the reference has it; a static
/// arrow under Reduce Motion.
struct PerchArrowCue: View {
    let pointsLeft: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudged = false
    @State private var nudges = 0

    var body: some View {
        Image(systemName: pointsLeft ? "arrow.left" : "arrow.right")
            .font(Perch.text(17, .semibold))
            .foregroundStyle(Perch.accentText)
            .offset(x: nudged ? (pointsLeft ? -7 : 7) : 0)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                nudge()
            }
    }

    private func nudge() {
        guard nudges < 3 else { return }
        nudges += 1
        withAnimation(.easeInOut(duration: 0.45)) { nudged = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.45)) { nudged = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nudge() }
        }
    }
}

// MARK: - The picker

/// The side's windows, one row each, with the arrow keys' place marked.
/// The pointer resting on a row stands on it too; a click connects it;
/// the highlight over the window on screen follows either.
struct PerchWindowPickerList: View {
    let controller: RelayController
    let picker: WindowPicker

    private var setup: SetupController { controller.setup }

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(3)) {
            Text("Choose a \(setup.name(picker.side)) window")
                .font(Perch.text(12, .medium))
                .foregroundStyle(Perch.muted)
            ScrollView(.vertical) {
                VStack(spacing: 1) {
                    ForEach(Array(picker.candidates.enumerated()), id: \.element.id) { index, candidate in
                        row(candidate, highlighted: index == picker.highlighted)
                    }
                }
            }
            .frame(maxHeight: Perch.s(96))
            Text(setup.problem ?? "\u{2191}\u{2193} move \u{00B7} Return connects \u{00B7} Esc cancels")
                .font(Perch.text(11))
                .foregroundStyle(setup.problem == nil ? Perch.placeholder : Perch.red)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Windows")
    }

    private func row(_ candidate: WindowCandidate, highlighted: Bool) -> some View {
        Button {
            setup.highlightPick(candidate.id)
            setup.choosePick()
        } label: {
            HStack(spacing: Perch.s(8)) {
                Text(candidate.name)
                    .font(Perch.text(12, .medium))
                    .foregroundStyle(Perch.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(candidate.identity.surface.map { "\($0) \u{00B7} \(candidate.context)" } ?? candidate.context)
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .lineLimit(1)
                Spacer(minLength: Perch.s(6))
                Text(candidate.stateLine)
                    .font(Perch.text(11))
                    .foregroundStyle(candidate.isEligible && candidate.composer.isEmpty ? Perch.green : Perch.red)
                    .lineLimit(1)
            }
            .padding(.horizontal, Perch.s(8))
            .frame(height: Perch.s(24))
            .background(RoundedRectangle(cornerRadius: Perch.s(6)).fill(highlighted ? Perch.well : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { setup.highlightPick(candidate.id) }
        }
        .accessibilityLabel("\(candidate.name), \(candidate.context), \(candidate.stateLine)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

// MARK: - Actions

/// The step's actions beside the center: one primary, with what else
/// the step offers under it.
struct PerchSetupActions: View {
    let controller: RelayController

    private var setup: SetupController { controller.setup }

    var body: some View {
        let state = setup.state
        VStack(alignment: .trailing, spacing: Perch.s(6)) {
            switch state.phase {
            case .prepareApps:
                PerchCapsuleButton(title: "Continue") { setup.continueFromPrepare() }
                    .disabled(!state.bothAvailable)
                    .keyboardShortcut(.defaultAction)
                    .help(state.bothAvailable ? "Both apps show a conversation" : "Open both apps first")
                if [Speaker.chatgpt, .claude].contains(where: { state[$0].presence == .notRunning }) {
                    PerchTextButton(title: "Open both apps") { setup.launchBoth() }
                }
            case .arrange:
                if state.layoutApplied {
                    PerchCapsuleButton(title: "Continue") { setup.continueFromArrange() }
                        .keyboardShortcut(.defaultAction)
                    if state.layout.movesWindows {
                        PerchTextButton(title: "Arrange again") { setup.applyLayout() }
                    }
                } else {
                    PerchCapsuleButton(title: state.layout.applyTitle) { setup.applyLayout() }
                        .disabled(state.layout.movesWindows && !state.canArrange)
                        .keyboardShortcut(.defaultAction)
                        .help(state.layout.movesWindows
                              ? "Move both chat windows into the layout"
                              : "Leave the windows where they are")
                }
                if setup.canRestoreLayout {
                    PerchTextButton(title: "Restore positions") { setup.restoreLayout() }
                }
            case .connect(let side):
                if setup.picker?.side == side {
                    PerchCapsuleButton(title: "Connect") { setup.choosePick() }
                        .disabled(setup.isBinding || setup.picker?.current?.isEligible != true)
                    PerchTextButton(title: "Cancel") { setup.cancelPicking() }
                } else {
                    PerchCapsuleButton(title: "Choose a window\u{2026}") { setup.beginPicking(side) }
                        .disabled(setup.isBinding || state[side].candidates.isEmpty)
                        .help("Pick the \(setup.name(side)) window to relay into")
                }
            case .compose:
                EmptyView()
            }
        }
        .fixedSize()
    }
}

// MARK: - Destination details

/// The connected side in full — app, surface, conversation, model, and
/// how it reads now — with the choices that belong to it: use a work
/// session deliberately, or choose another conversation.
struct PerchDestinationDetails: View {
    let controller: RelayController
    let speaker: Speaker
    var dismiss: () -> Void

    private var setup: SetupController { controller.setup }

    var body: some View {
        let side = setup.state[speaker]
        let name = setup.name(speaker)
        VStack(alignment: .leading, spacing: Perch.s(10)) {
            Text(name)
                .font(Perch.text(13, .semibold))
                .foregroundStyle(Perch.ink)
            if let connection = side.connection {
                detail("Conversation", connection.name)
                detail("Context", connection.context)
                detail("Surface", connection.identity.surface ?? "Not observed")
                detail("Model", connection.model ?? "Not observed")
                detail("Status", connection.readiness.problem(name: name) ?? "Ready to relay into")
                if case .needsSurfaceChoice(let surface) = connection.readiness {
                    Text("Messages relayed into this \(surface) session may lead to actions using that session's tools.")
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Perch.s(8)) {
                    if case .needsSurfaceChoice = connection.readiness {
                        PerchCapsuleButton(title: "Use this session") {
                            setup.acceptSurface(speaker)
                            dismiss()
                        }
                    }
                    PerchCapsuleButton(title: "Choose another conversation", style: .outlined) {
                        dismiss()
                        controller.chooseAnotherConversation(speaker)
                    }
                }
                .disabled(controller.isRunning)
            } else {
                detail("Status", side.presence.action(name: name))
                if let hint = side.hint { detail("Last used", hint.name) }
            }
        }
        .padding(Perch.s(14))
        .frame(width: Perch.s(340), alignment: .leading)
        .background(Perch.paper)
        .foregroundStyle(Perch.ink)
        .tint(Perch.accent)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(8)) {
            Text(label)
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .frame(width: Perch.s(76), alignment: .leading)
            Text(value)
                .font(Perch.text(12))
                .foregroundStyle(Perch.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

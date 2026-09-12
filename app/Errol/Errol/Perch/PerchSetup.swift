// The guided setup inside the capsule: the meter over the center, the
// center's instruction for each step with the step's actions under it,
// and the window picker with its keyboard. Screens 02–05 of the reference
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
                    .frame(height: progress == .current ? Perch.s(6) : Perch.s(4))
                    .frame(height: Perch.s(6))
                    .animation(Perch.fade, value: progress)
            }
        }
        .frame(maxWidth: Perch.s(124), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(state.progressDescription(names: controller.names))
    }

    private func color(_ progress: StepProgress) -> Color {
        switch progress {
        case .done: return Perch.green
        case .current: return Perch.setupCurrent
        case .remaining: return Perch.track
        }
    }
}

// MARK: - The center

/// The instruction for the current step with the step's actions under
/// it, where the editor sits later.
struct PerchSetupCenter: View {
    let controller: RelayController
    @FocusState private var focusedLayout: LayoutChoice?

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

    /// The step asks only that both apps be open; their conversations are
    /// the connect steps' concern. One primary action under the copy, as
    /// the reference has it: open what is not open, then go on.
    private var prepare: some View {
        let state = setup.state
        let missing = [Speaker.chatgpt, .claude].first { state[$0].presence == .notInstalled }
        let closed = [Speaker.chatgpt, .claude].contains { state[$0].presence == .notRunning }
        return VStack(alignment: .leading, spacing: Perch.s(8)) {
            copy(headline: state.bothOpen ? "Both apps are open." : "Bring your assistants.",
                 supporting: "Click each app\u{2019}s logo to open it. You\u{2019}ll choose the conversations next.",
                 problem: setup.problem ?? missing.flatMap { state[$0].presence.problem(name: name($0)) })
            if state.bothOpen {
                PerchCapsuleButton(title: "Continue", icon: "arrow.right") { setup.continueFromPrepare() }
                    .keyboardShortcut(.defaultAction)
                    .help("Go on to arranging the windows")
            } else {
                PerchCapsuleButton(title: "Open both apps", icon: "arrow.up.right") { setup.launchBoth() }
                    .disabled(!closed)
                    .keyboardShortcut(.defaultAction)
                    .help(closed ? "Open whichever app isn\u{2019}t open yet" : "Waiting for the apps to open")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Arrange

    /// The layout applies as it is chosen, so Continue is the only action,
    /// at the end of the choices' row as the reference has it; it waits
    /// only on a move in flight. Arranging again and putting the windows
    /// back live in the settings.
    private var arrange: some View {
        let state = setup.state
        return VStack(alignment: .leading, spacing: Perch.s(7)) {
            Text("Arrange the windows.")
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .fixedSize(horizontal: false, vertical: true)
            supportingLine(arrangeSupporting(state), problem: setup.problem ?? state.layoutProblem)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Perch.s(10)) {
                    layoutChoices
                    Spacer(minLength: 0)
                    arrangeContinue
                }
                VStack(alignment: .leading, spacing: Perch.s(8)) {
                    ViewThatFits(in: .horizontal) {
                        layoutChoices
                        VStack(alignment: .leading, spacing: Perch.s(7)) {
                            ForEach(LayoutChoice.allCases, id: \.self) { layoutButton($0) }
                        }
                    }
                    arrangeContinue.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.top, Perch.s(4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutChoices: some View {
        HStack(spacing: Perch.s(7)) {
            ForEach(LayoutChoice.allCases, id: \.self) { layoutButton($0) }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window arrangement. Choices apply immediately.")
    }

    private func layoutButton(_ layout: LayoutChoice) -> some View {
        PerchLayoutButton(layout: layout, selected: setup.state.layout == layout) {
            focusedLayout = layout
            setup.choose(layout)
        }
        .focused($focusedLayout, equals: layout)
    }

    private var arrangeContinue: some View {
        PerchCapsuleButton(title: "Continue") { setup.continueFromArrange() }
            .fixedSize()
            .disabled(setup.isArranging)
            .keyboardShortcut(.defaultAction)
            .help(setup.isArranging ? "Arranging the windows" : "Go on to connecting the conversations")
    }

    /// What the choice did, or waits on. A moving layout applies as it is
    /// chosen, so the line follows the arrangement; nothing gates Continue.
    private func arrangeSupporting(_ state: SetupState) -> String {
        guard state.layout.movesWindows else {
            return "Choose a layout to move both windows now, or continue as they are."
        }
        if let side = [Speaker.chatgpt, .claude].first(where: { state[$0].arrangementTarget == nil }) {
            return state[side].needsArrangementChoice
                ? "\(name(side)) has several windows: click its icon to choose the one to move."
                : "Open a conversation in \(name(side)) to move its window, or continue as things are."
        }
        if setup.isArranging { return "Arranging the windows\u{2026}" }
        if state.layoutApplied { return state.layout.completionMessage }
        return "Both chat windows move into the layout so you can watch the exchange."
    }

    // MARK: Connect

    private func connect(_ side: Speaker) -> some View {
        Group {
            if let picker = setup.picker, picker.side == side {
                VStack(alignment: .leading, spacing: Perch.s(8)) {
                    PerchWindowPickerList(controller: controller, picker: picker)
                    connectActions(side)
                }
            } else {
                connectInstruction(side)
            }
        }
    }

    /// The step's actions, under its copy: Choose a window, then Connect
    /// and Cancel while the picker is open.
    private func connectActions(_ side: Speaker) -> some View {
        HStack(spacing: Perch.s(8)) {
            if setup.picker?.side == side {
                PerchCapsuleButton(title: "Connect") { setup.choosePick() }
                    .disabled(setup.isBinding || setup.picker?.current?.isEligible != true
                              || setup.picker?.current?.isMinimized == true)
                PerchTextButton(title: "Cancel") { setup.cancelPicking() }
            } else {
                if side == .claude, setup.state.chatgpt.isConnected {
                    Label("\(name(.chatgpt)) connected", systemImage: "checkmark")
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.green)
                }
                PerchTextButton(title: "Click to choose a window") { setup.beginPicking(side) }
                    .disabled(setup.isBinding || setup.state[side].candidates.isEmpty)
                    .help("Pick the \(setup.name(side)) window to relay into")
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
            if leading { PerchArrowCue(pointsLeft: true).opacity(setup.draggingSide == nil ? 1 : 0) }
            VStack(alignment: leading ? .leading : .trailing, spacing: Perch.s(5)) {
                Text("Drag \(name(side)) onto its conversation.")
                    .font(Perch.text(19, .medium))
                    .foregroundStyle(Perch.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connectSupporting(side))
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                    .animation(Perch.fade, value: connectSupporting(side))
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
                }
                connectActions(side)
                    .padding(.top, Perch.s(3))
            }
            .multilineTextAlignment(leading ? .leading : .trailing)
            if !leading { PerchArrowCue(pointsLeft: false).opacity(setup.draggingSide == nil ? 1 : 0) }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    /// Under the instruction: whose messages the field will take, and,
    /// while the icon is being dragged, where to put it — the app has come
    /// forward with its message fields marked, so the drop teaches where
    /// Errol writes.
    private func connectSupporting(_ side: Speaker) -> String {
        if setup.draggingSide == side {
            guard let zones = setup.dropZones else { return "Bringing \(name(side)) forward\u{2026}" }
            if zones.isEmpty { return "No \(name(side)) conversation is showing. Open a chat in it first." }
            return "Drop it on the marked message field. That is where Errol pastes and sends."
        }
        return controller.firstSpeaker == side
            ? "Choose where your first message will go."
            : "Choose where \(name(other(than: side)))'s replies will land."
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
            .fixedSize(horizontal: false, vertical: true)
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

/// Independent actions with a persistent check, rather than a segmented
/// preference picker. The check keeps selection visible without color.
private struct PerchLayoutButton: View {
    let layout: LayoutChoice
    let selected: Bool
    let action: () -> Void

    private var symbol: String {
        switch layout {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        case .keepPositions: return "macwindow.on.rectangle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Perch.s(5)) {
                Image(systemName: symbol).font(Perch.text(13))
                Text(layout.title).font(Perch.text(11)).fixedSize()
                Image(systemName: "checkmark")
                    .font(Perch.text(9, .semibold))
                    .frame(width: Perch.s(11))
                    .opacity(selected ? 1 : 0)
            }
            .foregroundStyle(selected ? Perch.accentText : Perch.ink)
            .padding(.horizontal, Perch.s(8))
            .frame(height: Perch.s(29))
            .background(RoundedRectangle(cornerRadius: Perch.s(7))
                .fill(selected ? Perch.accentBack : Perch.paper))
            .overlay(RoundedRectangle(cornerRadius: Perch.s(7))
                .stroke(selected ? Perch.accent : Perch.chipEdge, lineWidth: 1))
            .perchHover(RoundedRectangle(cornerRadius: Perch.s(7)))
            .contentShape(RoundedRectangle(cornerRadius: Perch.s(7)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(layout.movesWindows ? "Move both windows \(layout == .sideBySide ? "side by side" : "into a stack") now"
              : "Leave both windows where they are")
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
            .font(Perch.text(26, .medium))
            .foregroundStyle(Perch.setupCurrent)
            .frame(width: Perch.s(30))
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

// MARK: - Destination details

/// The connected side in full — app, surface, conversation, model, and
/// how it reads now — with the one choice that belongs to it: another
/// conversation. A Code session is named as one and connects like any chat.
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
                PerchCapsuleButton(title: "Choose another conversation", style: .outlined) {
                    dismiss()
                    controller.chooseAnotherConversation(speaker)
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

// The guided setup inside the capsule: the meter over the center, the
// title below it, supporting copy beside the trailing action, and the
// arrow that says which icon to drag. Arrange has choices without status copy.
// Screens 02–05 of the reference
// (docs/design-proposals/setup-interaction/SPEC.md); the participants'
// columns and the destination details are in PerchAvatar.swift.

import SwiftUI

// MARK: - Progress

/// Four fixed tracks and one thicker accent marker that slides between
/// them. Completed tracks turn green as the marker moves to the next step.
/// Color alone carries nothing: the meter speaks its step to VoiceOver.
struct PerchProgressMeter: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = controller.setup.state
        let steps = SetupStep.allCases
        let current = steps.firstIndex { state.progress(of: $0) == .current }
        let gap = Perch.s(5)
        ZStack(alignment: .leading) {
            HStack(spacing: gap) {
                ForEach(steps, id: \.rawValue) { step in
                    Capsule()
                        .fill(state.progress(of: step) == .done ? Perch.green : Perch.track)
                        .frame(height: Perch.s(4))
                }
            }
            if let current {
                GeometryReader { geometry in
                    let segment = max(0, (geometry.size.width - gap * CGFloat(steps.count - 1)) / CGFloat(steps.count))
                    Capsule()
                        .fill(Perch.setupCurrent)
                        .frame(width: segment, height: Perch.s(6))
                        .offset(x: CGFloat(current) * (segment + gap))
                }
                .transition(.opacity)
            }
        }
        .frame(height: Perch.s(6))
        .frame(height: Perch.s(24))
        .frame(maxWidth: Perch.s(124), alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: current)
        .overlay {
            // A comfortable target inside the existing toolbar height. The
            // thin tracks retain their visual size and the marker stays clear.
            HStack(spacing: gap) {
                ForEach(steps, id: \.rawValue) { step in
                    Button { controller.setup.revisit(step) } label: {
                        Color.clear.frame(height: Perch.s(24)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.setup.canRevisit(step))
                    .help(step.title(names: controller.names))
                    .accessibilityLabel("Step \(step.rawValue + 1): \(step.title(names: controller.names))")
                    .accessibilityValue(state.currentStep == step ? "Current step"
                                        : controller.setup.canRevisit(step) ? "Go back" : "Unavailable")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup steps")
        .accessibilityValue(state.progressDescription(names: controller.names))
    }
}

// MARK: - The center

/// The title stays immediately below the toolbar. Supporting copy shares
/// the next row with its trailing action; Arrange needs only its choices.
struct PerchSetupCenter: View {
    let controller: RelayController
    @State private var showingArrangementProblem = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var setup: SetupController { controller.setup }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch setup.state.phase {
            case .prepareApps: prepare.transition(.opacity)
            case .arrange: arrange.transition(.opacity)
            case .connect(let side): connectInstruction(side)
            case .compose: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                   value: setup.state.phase == .prepareApps)
    }

    private var prepare: some View {
        let state = setup.state
        let missing = [Speaker.chatgpt, .claude].first { state[$0].presence == .notInstalled }
        let problem = setup.problem ?? missing.flatMap { state[$0].presence.problem(name: setup.name($0)) }
        let supporting = state.bothOpen ? "Next, choose how to arrange the windows."
            : "Click each app’s logo to open it. You’ll choose the conversations next."
        return VStack(alignment: .leading, spacing: Perch.s(12)) {
            title(state.bothOpen ? "Both apps are open." : "Bring your assistants.")
            HStack(spacing: Perch.s(14)) {
                supportingLine(supporting, problem: problem)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PerchSetupActions(controller: controller)
            }
        }
    }

    private var arrange: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            HStack(spacing: Perch.s(8)) {
                title("Arrange the windows.")
                if let problem = arrangementProblem {
                    Button { showingArrangementProblem.toggle() } label: {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Perch.red)
                    }
                    .buttonStyle(.plain)
                    .help(problem)
                    .accessibilityLabel("Window arrangement needs attention: \(problem)")
                    .popover(isPresented: $showingArrangementProblem) {
                        Text(problem)
                            .font(Perch.text(12))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Perch.s(14))
                            .frame(width: Perch.s(300))
                    }
                }
            }
            HStack(spacing: Perch.s(12)) {
                PerchLayoutChoices(controller: controller)
                Spacer(minLength: 0)
                PerchSetupActions(controller: controller)
            }
        }
    }

    /// Normal layout selection needs no narration. Preserve actionable
    /// failures and missing-window guidance on demand without adding a row.
    private var arrangementProblem: String? {
        let state = setup.state
        if let problem = setup.problem ?? state.layoutProblem { return problem }
        guard state.layout.movesWindows,
              let side = [Speaker.chatgpt, .claude].first(where: { state[$0].arrangementTarget == nil })
        else { return nil }
        return state[side].needsArrangementChoice
            ? "\(setup.name(side)) has several windows. Click its icon to choose the one to move."
            : "Open a conversation in \(setup.name(side)) to move its window, or continue as things are."
    }

    private func connectInstruction(_ side: Speaker) -> some View {
        let leading = side == .chatgpt
        return VStack(alignment: .leading, spacing: Perch.s(12)) {
            HStack(spacing: Perch.s(10)) {
                if leading { PerchArrowCue(pointsLeft: true).opacity(setup.draggingSide == nil ? 1 : 0) }
                ViewThatFits(in: .horizontal) {
                    title("Drag \(setup.name(side)) onto its conversation.").fixedSize()
                    title("Connect \(setup.name(side)).")
                }
                    .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
                    .multilineTextAlignment(leading ? .leading : .trailing)
                    .help("Drag \(setup.name(side)) onto its conversation, or choose a window.")
                if !leading { PerchArrowCue(pointsLeft: false).opacity(setup.draggingSide == nil ? 1 : 0) }
            }
            HStack(spacing: Perch.s(14)) {
                VStack(alignment: leading ? .leading : .trailing, spacing: Perch.s(3)) {
                    supportingLine(connectSupporting(side), problem: setup.problem)
                    if side == .claude, setup.state.chatgpt.isConnected, setup.problem == nil {
                        Label("\(setup.name(.chatgpt)) connected", systemImage: "checkmark")
                            .font(Perch.text(11)).foregroundStyle(Perch.green)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
                .multilineTextAlignment(leading ? .leading : .trailing)
                PerchSetupActions(controller: controller)
            }
        }
    }

    private func connectSupporting(_ side: Speaker) -> String {
        if let dragging = setup.draggingSide {
            guard let zones = setup.dropZones else { return "Bringing \(setup.name(dragging)) forward…" }
            if zones.isEmpty { return "No \(setup.name(dragging)) conversation is showing. Open a chat in it first." }
            return "Drop it on the marked message field. That is where Errol pastes and sends."
        }
        return controller.firstSpeaker == side
            ? "Choose where your first message will go."
            : "Choose where \(setup.name(side == .chatgpt ? .claude : .chatgpt))'s replies will land."
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(Perch.text(19, .medium))
            .foregroundStyle(Perch.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
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
}

/// The guided step's one action occupies the same trailing slot beneath
/// Configure. The setup center owns its title, copy, and layout choices.
struct PerchSetupActions: View {
    let controller: RelayController
    @State private var showingWindows = false

    private var setup: SetupController { controller.setup }

    var body: some View {
        switch setup.state.phase {
        case .prepareApps:
            if setup.state.bothOpen {
                PerchPrepareContinue(automatically: setup.state.automaticallyContinuePreparation) {
                    setup.continueFromPrepare()
                }
            } else {
                let closed = [Speaker.chatgpt, .claude].contains { setup.state[$0].presence == .notRunning }
                PerchRevealButton(title: "Open both apps", icon: "arrow.up.right") { setup.launchBoth() }
                    .disabled(!closed)
                    .keyboardShortcut(.defaultAction)
                    .help(closed ? "Open whichever app isn’t open yet" : "Waiting for the apps to open")
            }
        case .arrange:
            PerchRevealButton(title: "Continue", icon: "arrow.right") { setup.continueFromArrange() }
                .disabled(setup.isArranging)
                .keyboardShortcut(.defaultAction)
                .help(setup.isArranging ? "Arranging the windows" : "Go on to connecting the conversations")
        case .connect(let side):
            if setup.state[side].isConnected {
                PerchRevealButton(title: "Continue", icon: "arrow.right") { setup.continueFromConnection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.isBinding)
            } else {
                PerchRevealButton(title: "Choose a window", icon: "cursorarrow", prominent: false) {
                    showingWindows.toggle()
                }
                .disabled(setup.isBinding)
                .popover(isPresented: $showingWindows) { windowPicker(side) }
            }
        case .compose: EmptyView()
        }
    }

    private func windowPicker(_ side: Speaker) -> some View {
        VStack(alignment: .leading, spacing: Perch.s(10)) {
            Text("Choose the \(setup.name(side)) conversation")
                .font(Perch.text(13, .semibold))
            if setup.state[side].eligible.isEmpty {
                Text("Open a conversation in \(setup.name(side)), then choose its window here or drag its icon onto the message field.")
                    .font(Perch.text(12)).fixedSize(horizontal: false, vertical: true)
                PerchTextButton(title: "Bring \(setup.name(side)) forward") { setup.openConversation(side) }
            }
            ForEach(setup.state[side].eligible) { candidate in
                Button {
                    showingWindows = false
                    setup.connect(side, to: candidate.id)
                } label: {
                    VStack(alignment: .leading, spacing: Perch.s(3)) {
                        Text(candidate.name).font(Perch.text(12, .medium))
                        Text(candidate.stateLine).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Perch.s(8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .perchHover(RoundedRectangle(cornerRadius: Perch.s(7)))
            }
        }
        .padding(Perch.s(14))
        .frame(width: Perch.s(310))
    }
}

/// Choices remain directly under Arrange's title. On a narrow display the
/// same three actions keep their symbols, tooltips, and accessible names.
private struct PerchLayoutChoices: View {
    let controller: RelayController
    @FocusState private var focusedLayout: LayoutChoice?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            choices(showTitles: true)
            choices(showTitles: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window arrangement. Choices apply immediately.")
    }

    private func choices(showTitles: Bool) -> some View {
        HStack(spacing: Perch.s(7)) {
            ForEach(LayoutChoice.allCases, id: \.self) { layout in
                PerchLayoutButton(layout: layout, selected: controller.setup.state.layout == layout,
                                  showTitle: showTitles) {
                    focusedLayout = layout
                    controller.setup.choose(layout)
                }
                .focused($focusedLayout, equals: layout)
            }
        }
        .fixedSize()
    }
}

/// Mounted only while both apps are open. Readiness loss or leaving the
/// screen removes it and cancels its task; repeated readiness sweeps do not
/// restart the countdown. The state still rechecks readiness when advancing.
private struct PerchPrepareContinue: View {
    let automatically: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    private let duration: TimeInterval = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30,
                                paused: startedAt == nil)) { timeline in
            let elapsed = startedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0
            let seconds = max(1, Int(ceil(duration - elapsed)))
            PerchRevealButton(title: "Continue", icon: "arrow.right",
                              progress: !automatically || reduceMotion ? nil : elapsed / duration,
                              countdown: automatically ? seconds : nil, action: action)
                .monospacedDigit()
                .keyboardShortcut(.defaultAction)
                .help("Go on to arranging the windows now")
                .accessibilityLabel("Continue to arrange windows")
                .accessibilityValue(automatically ? "Automatically continues in \(seconds) seconds" : "")
        }
        .task(id: automatically) {
            guard automatically else { startedAt = nil; return }
            startedAt = .now
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard !Task.isCancelled, automatically else { return }
            action()
        }
    }
}

/// Independent actions with a persistent check, rather than a segmented
/// preference picker. The check keeps selection visible without color.
private struct PerchLayoutButton: View {
    let layout: LayoutChoice
    let selected: Bool
    var showTitle = true
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
                if showTitle { Text(layout.title).font(Perch.text(11)).fixedSize() }
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
                PerchCapsuleButton(title: "Choose another conversation", style: .glass) {
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

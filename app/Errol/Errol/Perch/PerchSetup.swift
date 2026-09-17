// The guided setup inside the capsule: the meter over the center, the
// center's instruction for each step with the step's actions along the
// capsule's bottom band, and the arrow that says which icon to drag.
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

/// The instruction for the current step: the copy that flows down from
/// under the meter. The step's actions stand along the capsule's bottom
/// band instead (PerchSetupActions), where the editor's Send sits later.
struct PerchSetupCenter: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var setup: SetupController { controller.setup }
    private var names: (chatgpt: String, claude: String) { controller.names }

    var body: some View {
        ZStack(alignment: .leading) {
            switch setup.state.phase {
            case .prepareApps: prepare.transition(.opacity)
            case .arrange: arrange.transition(.opacity)
            case .connect(let side): connectInstruction(side)
            case .compose: EmptyView()
            }
        }
        // Fade only the Open apps / Arrange handoff. The capsule, meter,
        // participant identities, and later editor keep their own lifetimes.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                   value: setup.state.phase == .prepareApps)
    }

    // MARK: Prepare

    /// The step asks only that both apps be open; their conversations are
    /// the connect steps' concern.
    private var prepare: some View {
        let state = setup.state
        let missing = [Speaker.chatgpt, .claude].first { state[$0].presence == .notInstalled }
        return copy(headline: state.bothOpen ? "Both apps are open." : "Bring your assistants.",
                    supporting: state.bothOpen ? "Next, choose how to arrange the windows."
                        : "Click each app\u{2019}s logo to open it. You\u{2019}ll choose the conversations next.",
                    problem: setup.problem ?? missing.flatMap { state[$0].presence.problem(name: name($0)) })
    }

    // MARK: Arrange

    /// The layout applies as it is chosen, so the line follows the
    /// arrangement; the choices and Continue are the bottom band's.
    private var arrange: some View {
        let state = setup.state
        return VStack(alignment: .leading, spacing: Perch.s(7)) {
            Text("Arrange the windows.")
                .font(Perch.text(19, .medium))
                .foregroundStyle(Perch.ink)
                .fixedSize(horizontal: false, vertical: true)
            supportingLine(arrangeSupporting(state), problem: setup.problem ?? state.layoutProblem)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The instruction block, with the arrow at the edge nearest the icon
    /// it points at: leading and left-pointing for ChatGPT, trailing and
    /// right-pointing for Claude, whose block is right-aligned to match.
    private func connectInstruction(_ side: Speaker) -> some View {
        let leading = side == .chatgpt
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
                }
            }
            .multilineTextAlignment(leading ? .leading : .trailing)
            if !leading { PerchArrowCue(pointsLeft: false).opacity(setup.draggingSide == nil ? 1 : 0) }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    /// Under the instruction: whose messages the field will take, and,
    /// while an icon is being dragged — this step's, or the other side's
    /// connected already and dragged again — where to put it: the app has
    /// come forward with its message fields marked, so the drop teaches
    /// where Errol writes.
    private func connectSupporting(_ side: Speaker) -> String {
        if let dragging = setup.draggingSide {
            guard let zones = setup.dropZones else { return "Bringing \(name(dragging)) forward\u{2026}" }
            if zones.isEmpty { return "No \(name(dragging)) conversation is showing. Open a chat in it first." }
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

// MARK: - The actions

/// The guided step's actions, along the capsule's bottom band: Open both
/// apps or Continue while preparing, at the leading edge; on Arrange,
/// Continue at the leading edge with the layout choices at the trailing
/// one; on the connect steps, the first side's connected mark and — on a
/// revisited step whose side is still bound — Continue, at the trailing
/// edge. The drag itself has no button: the icon is the control.
struct PerchSetupActions: View {
    let controller: RelayController
    @FocusState private var focusedLayout: LayoutChoice?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var setup: SetupController { controller.setup }

    var body: some View {
        ZStack(alignment: .leading) {
            switch setup.state.phase {
            case .prepareApps: prepare.transition(.opacity)
            case .arrange: arrange.transition(.opacity)
            case .connect(let side):
                if hasConnectActions(side) { connect(side) }
            case .compose: EmptyView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                   value: setup.state.phase == .prepareApps)
    }

    // MARK: Prepare

    /// One primary action: open what is not open, then go on.
    private var prepare: some View {
        let state = setup.state
        let closed = [Speaker.chatgpt, .claude].contains { state[$0].presence == .notRunning }
        return Group {
            if state.bothOpen {
                PerchPrepareContinue(automatically: state.automaticallyContinuePreparation) {
                    setup.continueFromPrepare()
                }
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

    /// Continue leads the row and the layout choices close it. Continue
    /// waits only on a move in flight; arranging again and putting the
    /// windows back live in the settings.
    private var arrange: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Perch.s(10)) {
                arrangeContinue
                Spacer(minLength: 0)
                layoutChoices
            }
            VStack(alignment: .leading, spacing: Perch.s(8)) {
                ViewThatFits(in: .horizontal) {
                    layoutChoices
                    VStack(alignment: .leading, spacing: Perch.s(7)) {
                        ForEach(LayoutChoice.allCases, id: \.self) { layoutButton($0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                arrangeContinue
            }
        }
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

    // MARK: Connect

    /// Whether the step has anything in the band: the first side's
    /// connected mark on the second step, or Continue on a revisited step
    /// whose side is still bound.
    private func hasConnectActions(_ side: Speaker) -> Bool {
        (side == .claude && setup.state.chatgpt.isConnected) || setup.state[side].isConnected
    }

    private func connect(_ side: Speaker) -> some View {
        HStack(spacing: Perch.s(10)) {
            Spacer(minLength: 0)
            if side == .claude, setup.state.chatgpt.isConnected {
                Label("\(setup.name(.chatgpt)) connected", systemImage: "checkmark")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.green)
            }
            if setup.state[side].isConnected {
                PerchCapsuleButton(title: "Continue") { setup.continueFromConnection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.isBinding)
            }
        }
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
            PerchCapsuleButton(title: automatically ? "Continue · \(seconds)" : "Continue",
                               icon: "arrow.right",
                               progress: !automatically || reduceMotion ? nil : elapsed / duration,
                               action: action)
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

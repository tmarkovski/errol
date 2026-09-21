// A participant's column at either end of the capsule: the installed
// app's icon and one line under it. The line is the status when there is
// one — replying, opening, the connected conversation, the next thing to
// do, what is wrong — and the app's name only when there is not; the icon
// says which app it is the rest of the time. A corner mark shows the
// connection. ChatGPT stands left and Claude right whoever starts. The
// icon is the side's control and changes with the step: it opens the app,
// is dragged to connect its conversation, or shows the destination's
// details; it never changes who starts, which the session settings do.
//
// Dragging an icon connects a window: the app comes forward under the
// console with an area drawn over each message field, and the drop lands
// on one of those. Errol owns the gesture and sends no file to the other
// app. Through both connect steps either open app's icon can be dragged,
// a connected one again — the step names one side, but the gesture is the
// lesson in where Errol writes, and repeating it costs nothing.
//
// On the direct console (PerchConsole.swift) there are no steps and no
// drag: beside the editor the icon opens its app, brings it forward for a
// chat to be opened in it, or — where the app shows several conversations —
// offers them in a menu, and one chosen there is connected.

import SwiftUI

struct PerchParticipant: View {
    let controller: RelayController
    let speaker: Speaker
    @State private var showingDetails = false
    @State private var hoveringIcon = false
    @FocusState private var iconFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var setup: SetupController { controller.setup }
    private var side: SideSetup { setup.state[speaker] }
    private var status: SideStatus {
        speaker == .chatgpt ? controller.chatgptStatus : controller.claudeStatus
    }
    private var conversation: ConversationStatus {
        speaker == .chatgpt ? controller.chatgptConversation : controller.claudeConversation
    }
    private var bundleID: String {
        speaker == .chatgpt ? config.chatgptBundleID : config.claudeBundleID
    }
    private var name: String { status.appName }
    private var feather: Color { speaker == .claude ? Perch.claudeFeather : Perch.chatgptFeather }
    private var replying: Bool { controller.isRunning && conversation == .chatting }

    /// What a click on the icon does now. Dragging is `draggable`'s
    /// concern and outlives the role: a connected side shows its details
    /// on a click and connects again on a drag.
    private enum Role {
        case launch, openConversation, connect, chooseArrangement, chooseConversation, details, none
    }

    private var role: Role {
        switch controller.stage {
        case .running:
            return .none
        case .compose, .finished:
            if side.isConnected { return .details }
            // Only the direct console reaches the editor with a side
            // still unconnected.
            guard controller.stage == .compose else { return .none }
            switch side.presence {
            case .notRunning: return .launch
            case .noWindow, .noConversation: return .openConversation
            case .available: return setup.state.needsConversationChoice(speaker) ? .chooseConversation : .none
            default: return .none
            }
        case .setup:
            switch setup.state.phase {
            case .prepareApps:
                switch side.presence {
                case .notRunning: return .launch
                case .noWindow, .noConversation: return .openConversation
                default: return .none
                }
            case .arrange:
                return setup.state.needsArrangementChoice(speaker)
                    ? .chooseArrangement : (side.isConnected ? .details : .none)
            case .connect(let target):
                if target == speaker { return .connect }
                return side.isConnected ? .details : .none
            case .compose:
                return .details
            }
        }
    }

    /// Whether the icon can be dragged onto a conversation: through the
    /// connect steps, for either side whose app is open.
    private var draggable: Bool {
        guard controller.stage == .setup, setup.state.phase.isConnecting else { return false }
        return side.presence.isOpen
    }

    var body: some View {
        VStack(spacing: Perch.s(4)) {
            icon
                // Where this side's replies set off from
                // (RelayController.iconTransferSources).
                .background {
                    if let source = controller.iconTransferSources[speaker] {
                        PromptTransferProbe(source: source)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            statusLine
        }
        .frame(width: Perch.participantWidth)
        .animation(Perch.fade, value: line)
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            PerchDestinationDetails(controller: controller, speaker: speaker) { showingDetails = false }
        }
        .help(details)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityValue(details)
    }

    // MARK: The icon

    private var preparationLabel: String? {
        guard (controller.stage == .setup && setup.state.phase == .prepareApps)
                || (controller.stage == .compose && setup.isDirect) else { return nil }
        switch side.presence {
        case .launching: return "Opening\u{2026}"
        case .checking: return "Checking\u{2026}"
        default: return nil
        }
    }

    private var iconOpacity: Double {
        if controller.stage == .setup || controller.stage == .compose, !side.presence.isOpen { return 0.45 }
        return controller.isRunning && !replying ? 0.7 : 1
    }

    @ViewBuilder private var icon: some View {
        let avatar = PerchAvatar(bundleID: bundleID, initial: String(name.prefix(1)), feather: feather,
                                 presence: presence, check: connectedAndReady)
            .modifier(PerchLaunchBounce(isLaunching: !controller.isRunning && side.presence == .launching))
            .opacity(iconOpacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: iconOpacity)
            .brightness(hoveringIcon && role != .none ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringIcon)
            .onHover { hoveringIcon = $0 }
        if role == .chooseArrangement || role == .chooseConversation {
            let connects = role == .chooseConversation
            Menu {
                ForEach(side.eligible) { candidate in
                    Button("\(candidate.name) \u{00B7} \(candidate.stateLine)") {
                        if connects {
                            setup.connect(speaker, to: candidate.id)
                        } else {
                            setup.chooseArrangementWindow(speaker, candidate.id)
                        }
                    }
                }
            } label: {
                avatar.contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focused($iconFocused)
            .accessibilityLabel(iconLabel)
        } else {
            Button(action: act) {
                avatar
                    .contentShape(Rectangle())
            }
            .buttonStyle(PerchIconButtonStyle())
            .disabled(role == .none || role == .connect)
            .focused($iconFocused)
            .accessibilityLabel(iconLabel)
            .overlay {
                if draggable {
                    // The handle takes the mouse over the icon, so a plain
                    // click comes back through it to do what the role says.
                    PerchConnectionDragHandle(setup: setup, side: speaker, onClick: act)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func act() {
        switch role {
        case .launch: setup.launch(speaker)
        case .openConversation: setup.openConversation(speaker)
        case .details: showingDetails = true
        case .connect, .chooseArrangement, .chooseConversation, .none: break
        }
    }

    private var iconLabel: String {
        switch role {
        case .launch: return "Open \(name)"
        case .openConversation: return "Bring \(name) forward"
        case .connect: return "Drag \(name) onto its conversation"
        case .details: return "\(name) destination details"
        case .chooseArrangement: return "Choose which \(name) window to move"
        case .chooseConversation: return "Choose which \(name) conversation to connect"
        case .none: return name
        }
    }

    // MARK: The line

    /// What stands under the icon. Whichever it is, the slot has the same
    /// height, so the icon stays where it is as the status comes and goes.
    private enum Line: Equatable {
        case name
        case status(String, isProblem: Bool)
        case replying
    }

    private var line: Line {
        if replying { return .replying }
        if let preparationLabel { return .status(preparationLabel, isProblem: false) }
        if let (text, isProblem) = stateLine { return .status(text, isProblem: isProblem) }
        return .name
    }

    private var statusLine: some View {
        ZStack {
            switch line {
            case .name:
                PerchAppLabel(name: name, hintActive: role == .launch && (hoveringIcon || iconFocused))
                    .transition(.opacity)
            case .status(let text, let isProblem):
                Text(text)
                    .font(Perch.text(11))
                    .foregroundStyle(isProblem ? Perch.red : Perch.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            case .replying:
                replyingDots.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Perch.s(17))
    }

    private var connectedAndReady: Bool {
        side.connection?.readiness.isReady == true
    }

    /// The mark's color once the side is connected: how its conversation
    /// reads. Before that the corner stays bare, as the reference has it.
    private var presence: Color? {
        guard let connection = side.connection else { return nil }
        switch connection.readiness {
        case .ready: return Perch.presence
        case .unverified: return Perch.path
        default: return Perch.red
        }
    }

    /// What the line says when the app's name is not enough: a drag in
    /// progress first, then the connected conversation and how it reads, or
    /// the next thing to do for the app at this step. Nil when there is
    /// nothing to add to the name.
    private var stateLine: (String, Bool)? {
        if controller.stage == .setup, setup.draggingSide == speaker {
            return (setup.dragCandidate == nil ? "Drag to the field" : "Release to connect", false)
        }
        if let connection = side.connection {
            switch connection.readiness {
            case .ready: return (connection.name, false)
            case .unverified: return ("Last used", false)
            default: return (connection.readiness.status(name: name), true)
            }
        }
        if side.presence == .notInstalled { return ("Not installed", true) }
        switch controller.stage {
        case .compose:
            return role == .chooseConversation ? ("Choose a chat", false) : nil
        case .running, .finished:
            return nil
        case .setup:
            switch setup.state.phase {
            case .prepareApps:
                return nil
            case .arrange:
                if setup.state.needsArrangementChoice(speaker) { return ("Choose a window", false) }
                return side.presence.isOpen ? nil : (side.presence.openState, false)
            case .connect(let target):
                if target == speaker { return ("Drag to connect", false) }
                return side.presence.isOpen ? nil : (side.presence.openState, false)
            case .compose:
                return nil
            }
        }
    }

    private var replyingDots: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduceMotion)) { context in
            HStack(spacing: Perch.s(3)) {
                ForEach(0..<3) { index in
                    Circle().fill(Perch.accentText)
                        .opacity(reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 3) % 3 == index ? 1 : 0.3)
                        .frame(width: Perch.s(4), height: Perch.s(4))
                }
            }
        }
        .accessibilityLabel("Replying")
    }

    private var details: String {
        var parts = [name]
        if let connection = side.connection {
            parts.append(connection.name)
            parts.append(connection.context)
            if let surface = connection.identity.surface { parts.append(surface) }
            if let model = connection.model { parts.append(model) }
            if let problem = connection.readiness.problem(name: name) { parts.append(problem) }
        } else {
            parts.append(side.presence.action(name: name))
            if let surface = status.surface { parts.append(surface) }
        }
        if replying { parts.append("Replying") }
        if controller.firstSpeaker == speaker, controller.stage == .compose { parts.append("Starts the conversation") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Availability controls icon opacity. The standard plain button style
/// would also dim an open app whose icon currently has no action.
private struct PerchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// The app's name, for when nothing else needs saying: it rolls down to
/// briefly reveal its action. The accessible name stays stable while the
/// visual hint comes and goes.
private struct PerchAppLabel: View {
    let name: String
    let hintActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingHint = false

    var body: some View {
        ZStack {
            Text(name)
                .font(Perch.text(12, .medium))
                .foregroundStyle(Perch.ink)
                .offset(y: showingHint ? Perch.s(17) : 0)
            Text("Click to open")
                .font(Perch.text(11))
                .foregroundStyle(Perch.secondary)
                .offset(y: showingHint ? 0 : -Perch.s(17))
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: Perch.s(17))
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showingHint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .task(id: hintActive) {
            showingHint = false
            guard hintActive else { return }
            showingHint = true
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 1000 : 1180))
            } catch { return }
            showingHint = false
        }
    }
}

/// A Dock-style hop while launch is pending. Only the artwork moves; the
/// participant's labels, layout slot, and button target stay in place.
private struct PerchLaunchBounce: ViewModifier {
    let isLaunching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date.now

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isLaunching || reduceMotion)) { context in
            content
                .offset(y: offset(at: context.date))
                .transaction { $0.animation = nil }
        }
        .onChange(of: isLaunching) { _, _ in started = .now }
    }

    private func offset(at date: Date) -> CGFloat {
        guard isLaunching, !reduceMotion else { return 0 }
        let phase = max(0, date.timeIntervalSince(started)).truncatingRemainder(dividingBy: 1)
        let progress: Double
        let height: CGFloat
        if phase < 0.6 {
            progress = phase / 0.6
            height = Perch.s(12)
        } else if phase < 0.84 {
            progress = (phase - 0.6) / 0.24
            height = Perch.s(4)
        } else {
            return 0
        }
        return -4 * height * CGFloat(progress * (1 - progress))
    }
}

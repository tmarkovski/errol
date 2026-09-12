// A participant's column at either end of the capsule: the installed
// app's icon, its name, and under that what the side is now — the next
// thing to do for it, or the conversation it is connected to — with the
// mark in the icon's corner once it is connected. ChatGPT stands left and Claude right whoever starts. The
// icon is the side's control and changes with the step: it opens the app,
// chooses its window, or shows the destination's details; it never
// changes who starts, which the session settings do.
//
// Dragging the active icon selects a window through the same binding as
// the picker: the app comes forward under the console with an area drawn
// over each message field, and the drop lands on one of those. Errol owns
// the gesture and sends no file to the other app.

import SwiftUI

struct PerchParticipant: View {
    let controller: RelayController
    let speaker: Speaker
    @State private var showingDetails = false
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

    /// What the icon does now.
    private enum Role {
        case launch, openConversation, chooseWindow, chooseArrangement, details, none
    }

    private var role: Role {
        switch controller.stage {
        case .running:
            return .none
        case .compose, .finished:
            return side.isConnected ? .details : .none
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
                if target == speaker { return .chooseWindow }
                return side.isConnected ? .details : .none
            case .compose:
                return .details
            }
        }
    }

    var body: some View {
        VStack(spacing: Perch.s(4)) {
            icon
            Text(name)
                .font(Perch.text(12, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(1)
            Group {
                if replying {
                    replyingDots
                } else if let (text, isProblem) = stateLine {
                    Text(text)
                        .font(Perch.text(11))
                        .foregroundStyle(isProblem ? Perch.red : Perch.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                }
            }
            .frame(height: Perch.s(13))
        }
        .frame(width: Perch.participantWidth)
        .animation(Perch.fade, value: stateLine?.0)
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            PerchDestinationDetails(controller: controller, speaker: speaker) { showingDetails = false }
        }
        .help(details)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityValue(details)
    }

    // MARK: The icon

    @ViewBuilder private var icon: some View {
        let avatar = PerchAvatar(bundleID: bundleID, initial: String(name.prefix(1)), feather: feather,
                                 presence: presence, check: connectedAndReady)
            .opacity(controller.isRunning && !replying ? 0.7 : 1)
        if role == .chooseArrangement {
            Menu {
                ForEach(side.eligible) { candidate in
                    Button("\(candidate.name) \u{00B7} \(candidate.stateLine)") {
                        setup.chooseArrangementWindow(speaker, candidate.id)
                    }
                }
            } label: {
                avatar.contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Choose which \(name) window to move")
        } else {
            Button(action: act) {
                avatar
                    .perchHover(Circle(), opacity: role == .none ? 0 : 0.08)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(role == .none)
            .accessibilityLabel(iconLabel)
            .overlay {
                if role == .chooseWindow {
                    PerchConnectionDragHandle(setup: setup, side: speaker)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func act() {
        switch role {
        case .launch: setup.launch(speaker)
        case .openConversation: setup.openConversation(speaker)
        case .chooseWindow: setup.beginPicking(speaker)
        case .details: showingDetails = true
        case .chooseArrangement, .none: break
        }
    }

    private var iconLabel: String {
        switch role {
        case .launch: return "Open \(name)"
        case .openConversation: return "Bring \(name) forward"
        case .chooseWindow: return "Choose \(name)'s window"
        case .details: return "\(name) destination details"
        case .chooseArrangement: return "Choose which \(name) window to move"
        case .none: return name
        }
    }

    // MARK: The lines

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

    /// The state under the app's name: the connected conversation and how
    /// it reads, or the next thing to do for the app at this step. The
    /// reference keeps the name on top and the state under it throughout.
    private var stateLine: (String, Bool)? {
        if let connection = side.connection {
            switch connection.readiness {
            case .ready: return (connection.name, false)
            case .unverified: return ("Last used", false)
            default: return (connection.readiness.status(name: name), true)
            }
        }
        if side.presence == .notInstalled { return ("Not installed", true) }
        switch controller.stage {
        case .running, .finished, .compose:
            return nil
        case .setup:
            switch setup.state.phase {
            case .prepareApps:
                return (side.presence.openState, false)
            case .arrange:
                if setup.state.needsArrangementChoice(speaker) { return ("Choose a window", false) }
                return (side.presence.openState, false)
            case .connect(let target):
                if target == speaker {
                    if setup.draggingSide == speaker {
                        return (setup.dragCandidate == nil ? "Drag to the field" : "Release to connect", false)
                    }
                    return (setup.picker?.side == speaker ? "Choosing\u{2026}" : "Drag to connect", false)
                }
                return (side.presence.openState, false)
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

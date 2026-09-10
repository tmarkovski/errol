// A participant's column at either end of the capsule: the installed
// app's icon over what the side is now — the next thing to do for it, or
// the conversation it is connected to — with the presence mark in the
// icon's corner. ChatGPT stands left and Claude right whoever starts. The
// icon is the side's control and changes with the step: it opens the app,
// chooses its window, or shows the destination's details; it never
// changes who starts, which the session settings do.
//
// The drag from this icon onto a window is the gesture the setup design
// leads with and is not built yet; when it is, it ends in the same
// `SetupController.connect(_:to:)` the picker uses.

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
                return side.needsArrangementChoice ? .chooseArrangement : (side.isConnected ? .details : .none)
            case .connect(let target):
                if target == speaker { return .chooseWindow }
                return side.isConnected ? .details : .none
            case .compose:
                return .details
            }
        }
    }

    var body: some View {
        VStack(spacing: Perch.s(6)) {
            icon
            Text(primaryLine)
                .font(Perch.text(11, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
            Group {
                if replying {
                    replyingDots
                } else if let (text, isProblem) = secondaryLine {
                    Text(text)
                        .font(Perch.text(10))
                        .foregroundStyle(isProblem ? Perch.red : Perch.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                }
            }
            .frame(height: Perch.s(12))
        }
        .frame(width: Perch.participantWidth)
        .animation(Perch.fade, value: primaryLine)
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

    private var presence: Color {
        if let connection = side.connection {
            switch connection.readiness {
            case .ready: return Perch.presence
            case .unverified: return Perch.path
            default: return Perch.red
            }
        }
        switch side.presence {
        case .available: return Perch.presence
        case .checking, .launching: return Perch.path
        case .notInstalled, .notRunning, .noWindow, .noConversation: return Perch.red
        }
    }

    private var primaryLine: String {
        if let connection = side.connection { return connection.name }
        switch controller.stage {
        case .running, .finished, .compose:
            return name
        case .setup:
            switch setup.state.phase {
            case .prepareApps:
                return side.presence.action(name: name)
            case .arrange:
                if side.needsArrangementChoice { return "Choose a window" }
                return side.eligible.first?.name ?? side.presence.action(name: name)
            case .connect(let target):
                if target == speaker { return setup.picker?.side == speaker ? "Choosing\u{2026}" : "Choose a window" }
                return side.presence.isAvailable ? "Not connected" : side.presence.action(name: name)
            case .compose:
                return name
            }
        }
    }

    private var secondaryLine: (String, Bool)? {
        if let connection = side.connection {
            if !connection.readiness.isReady, connection.readiness != .unverified {
                return (connection.readiness.status(name: name), true)
            }
            if connection.readiness == .unverified { return ("Last used", false) }
            return (connection.context, false)
        }
        if case .connect(let target) = setup.state.phase, target == speaker, let hint = side.hint {
            return ("Last used: \(hint.name)", false)
        }
        if case .setup = controller.stage, side.presence == .notInstalled {
            return ("Not on this Mac", true)
        }
        return nil
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

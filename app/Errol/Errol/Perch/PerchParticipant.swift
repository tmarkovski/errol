// A participant's column at either end of the console: the installed
// app's icon and one line under it. The line is the status when there is
// one — replying, opening, the connected conversation, the next thing to
// do, what is wrong — and the app's name only when there is not; the icon
// says which app it is the rest of the time. ChatGPT stands left and
// Claude right whoever starts. The icon is the side's control: a click
// opens the app when it is closed, and otherwise brings it forward — its
// connected window in front — and hands the keyboard straight back to
// the console; where the app shows several conversations, it offers them
// in a menu instead, and a connected side can be switched from the icon's
// context menu. It never changes who starts, which the Send pill does.
//
// Readiness reads from the icon itself: it stands faded until the side's
// conversation is connected and ready, and fades in once it is.

import SwiftUI

struct PerchParticipant: View {
    let controller: RelayController
    let speaker: Speaker
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

    /// What a click on the icon does now. Nothing during a run, which
    /// owns the apps' focus.
    private enum Role {
        case launch, bringForward, chooseConversation, none
    }

    private var role: Role {
        guard !controller.isRunning else { return .none }
        if side.isConnected { return .bringForward }
        switch side.presence {
        case .notRunning: return .launch
        case .noWindow, .noConversation: return .bringForward
        case .available: return side.needsConversationChoice ? .chooseConversation : .bringForward
        default: return .none
        }
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
        .help(details)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityValue(details)
    }

    // MARK: The icon

    private var preparationLabel: String? {
        guard controller.stage == .compose else { return nil }
        switch side.presence {
        case .launching: return "Opening\u{2026}"
        case .checking: return "Checking\u{2026}"
        default: return nil
        }
    }

    /// Faded until the side reads ready — the same evidence Send uses —
    /// and full once it does. During a run the side writing is the one
    /// at full strength.
    private var iconOpacity: Double {
        if controller.isRunning { return replying ? 1 : 0.7 }
        return side.isReady ? 1 : 0.45
    }

    @ViewBuilder private var icon: some View {
        let avatar = PerchAvatar(bundleID: bundleID, initial: String(name.prefix(1)), feather: feather)
            .modifier(PerchLaunchBounce(isLaunching: !controller.isRunning && side.presence == .launching))
            .opacity(iconOpacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: iconOpacity)
            .brightness(hoveringIcon && role != .none ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringIcon)
            .onHover { hoveringIcon = $0 }
        if role == .chooseConversation {
            Menu {
                ForEach(side.eligible) { candidate in
                    Button("\(candidate.name) \u{00B7} \(candidate.stateLine)") {
                        setup.connect(speaker, to: candidate.id)
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
            .disabled(role == .none)
            .focused($iconFocused)
            .accessibilityLabel(iconLabel)
            .contextMenu {
                if side.isConnected {
                    Button("Choose Another Conversation") { controller.chooseAnotherConversation(speaker) }
                        .disabled(controller.isRunning)
                }
            }
        }
    }

    private func act() {
        switch role {
        case .launch: setup.launch(speaker)
        case .bringForward: setup.bringForward(speaker)
        case .chooseConversation, .none: break
        }
    }

    private var iconLabel: String {
        switch role {
        case .launch: return "Open \(name)"
        case .bringForward: return "Bring \(name) forward"
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

    /// What the line says when the app's name is not enough: the connected
    /// conversation and how it reads, or the next thing to do for the app.
    /// Nil when there is nothing to add to the name.
    private var stateLine: (String, Bool)? {
        if let connection = side.connection {
            switch connection.readiness {
            case .ready: return (connection.name, false)
            case .unverified: return ("Last used", false)
            default: return (connection.readiness.status(name: name), true)
            }
        }
        if side.presence == .notInstalled { return ("Not installed", true) }
        return role == .chooseConversation ? ("Choose a chat", false) : nil
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

// What the console says about each side: its state, destination, click and tip facts.
// Its own file because the icon, its tip and the destination line all read it.

import AppKit
import SwiftUI

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
    /// An unverified connection is not one; the muted line already says it.
    var problem: String? { isRemembered ? nil : shortStatus }

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

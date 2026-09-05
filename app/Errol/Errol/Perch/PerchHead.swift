// The head: the two perches with their avatars (PerchAvatar — the apps'
// own icons) and presence dots, the dotted flight path between them with
// the courier bead riding it, and the turn line that says in one quiet
// sentence what the panel is doing. See PerchPanelView for the panel.

import SwiftUI

/// One view on purpose: everything here depends on the same relay-state
/// cluster, so splitting it further would add plumbing without separating
/// meaningful updates.
struct PerchHead: View {
    let controller: RelayController

    var body: some View {
        VStack(spacing: Perch.s(12)) {
            HStack(alignment: .top, spacing: 0) {
                perch(.chatgpt, status: controller.chatgptStatus,
                      conversation: controller.chatgptConversation,
                      feather: Perch.chatgptFeather)
                PerchFlightPath(fraction: beadFraction)
                    .padding(.top, Perch.s(2))
                perch(.claude, status: controller.claudeStatus,
                      conversation: controller.claudeConversation,
                      feather: Perch.claudeFeather)
            }
            turnLine
            if controller.isRunning || controller.hasFinishedRun {
                // The note's line: where it is during the run, what became
                // of it after, kept until New session since ending is when
                // someone inspects what happened. The slot is reserved for
                // the whole run, so the composer does not move under the
                // hand that starts typing a note.
                PerchSteeringLine(controller: controller)
                    .frame(height: Perch.s(14))
            }
            if controller.hasFinishedRun {
                newSessionButton
            }
        }
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var bothEnded: Bool {
        controller.chatgptConversation == .ended && controller.claudeConversation == .ended
    }

    // MARK: The perches

    private func perch(_ speaker: Speaker, status: SideStatus,
                       conversation: ConversationStatus, feather: Color) -> some View {
        let line = subline(status: status, conversation: conversation)
        return VStack(spacing: Perch.s(7)) {
            PerchAvatar(bundleID: bundleID(for: speaker),
                        initial: String(status.appName.prefix(1)), feather: feather,
                        presence: presenceColor(status: status, conversation: conversation))
            VStack(spacing: Perch.s(1)) {
                Text(status.appName)
                    .font(Perch.text(13, .semibold))
                    .foregroundColor(Perch.ink)
                Text(line)
                    .font(Perch.text(11))
                    .foregroundColor(Perch.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // "Replying…" shimmers: the one line that means busy.
                    .perchShimmer(active: conversation == .chatting)
                    .contentTransition(.opacity)
                    .animation(Perch.fade, value: line)
            }
        }
        .frame(width: Perch.s(132))
        // Clicking a perch nominates that side to open the next run; the
        // bead has no pointer here, so the turn line is the acknowledgement.
        // Disabled during a run so the hover wash stops with the click.
        .contentShape(Rectangle())
        .perchHover(RoundedRectangle(cornerRadius: Perch.s(12)))
        .onTapGesture {
            guard !controller.isRunning else { return }
            controller.firstSpeaker = speaker
        }
        .disabled(controller.isRunning)
        .help(controller.isRunning ? ""
              : "Have \(status.appName) send the opening message")
    }

    /// The avatar wears the icon of whichever app the side's bundle ID
    /// names, read at render time so a Settings change to the ID shows on
    /// the next refresh.
    private func bundleID(for speaker: Speaker) -> String {
        switch speaker {
        case .chatgpt: config.chatgptBundleID
        case .claude: config.claudeBundleID
        }
    }

    /// Green when the side is relayable, amber while it is the one composing,
    /// red when it is not relayable, and the path's gray while the first
    /// sweep is still out. One dot, not a pair of ready and live lamps: the
    /// turn line says the rest in words.
    private func presenceColor(status: SideStatus,
                               conversation: ConversationStatus) -> Color {
        if conversation == .chatting { return Perch.amber }
        if controller.isRunning { return Perch.presence }
        switch status.state {
        case .ready: return Perch.presence
        case .checking: return Perch.path
        case .notReady, .missing: return Perch.red
        }
    }

    /// Under the name: the side's part in the run while one is going, its
    /// diagnosis while it is not relayable, and its surface and model
    /// otherwise — identity when there is nothing to report.
    private func subline(status: SideStatus,
                         conversation: ConversationStatus) -> String {
        if controller.isRunning || controller.hasFinishedRun {
            switch conversation {
            case .chatting: return "Replying…"
            case .replied: return "Reply ready"
            case .ended: return "Signed off"
            case .waiting: return "Waiting"
            case .notStarted: return controller.isRunning ? "Waiting" : " "
            }
        }
        if status.state == .notReady || status.state == .missing {
            return status.headline
        }
        let parts = [status.surface, status.model].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    // MARK: The turn line

    /// One sentence, centered: the turn count and what is happening to it.
    /// This is where the precise copy lives — "Will pause after Claude
    /// finishes" rather than a bare "Paused" — because the pause states are
    /// exactly the ones a glance misreads. A hold reads the same whoever
    /// asked for it, the Pause control or a note being written; the line
    /// under this one says which.
    private var turnLine: some View {
        Text(turnText)
            .font(Perch.text(11))
            .foregroundColor(Perch.muted)
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(Perch.fade, value: turnText)
    }

    private var turnText: String {
        if controller.isRunning {
            let turn = "Turn \(controller.currentTurn)"
            if controller.isHolding { return "\(turn) · Paused at the handoff" }
            if controller.holdRequested {
                if let side = chattingName { return "\(turn) · Will pause after \(side) finishes" }
                return "\(turn) · Pausing at the next handoff"
            }
            if let side = chattingName { return "\(turn) · \(side) is replying" }
            return "\(turn) · Relaying"
        }
        if controller.hasFinishedRun {
            var line = bothEnded ? "Run complete" : "Run ended"
            line += " · \(controller.currentTurn) \(controller.currentTurn == 1 ? "turn" : "turns")"
            if let duration = controller.lastRunDuration {
                line += " · ran \(runClock(duration))"
            }
            return line
        }
        return "Turn 0 · \(openerName) opens"
    }

    private var chattingName: String? {
        if controller.chatgptConversation == .chatting { return controller.chatgptStatus.appName }
        if controller.claudeConversation == .chatting { return controller.claudeStatus.appName }
        return nil
    }

    private var openerName: String {
        switch controller.firstSpeaker {
        case .chatgpt: controller.chatgptStatus.appName
        case .claude: controller.claudeStatus.appName
        }
    }

    private func runClock(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// The bead parks under whichever side is composing and waits mid-arc
    /// when nobody is — before the run, between deliveries, and once a pause
    /// has parked a captured reply with the courier.
    private var beadFraction: CGFloat {
        if controller.isHolding { return 0.5 }
        if controller.chatgptConversation == .chatting { return 0.06 }
        if controller.claudeConversation == .chatting { return 0.94 }
        return 0.5
    }

    // MARK: New session

    /// The second step of the two-step ending: END leaves the finished run
    /// readable — the turn count, the sign-offs, the clock — and this is
    /// what clears it for the next one.
    private var newSessionButton: some View {
        Button {
            controller.resetSession()
        } label: {
            Text("New session")
                .font(Perch.text(11, .medium))
                .foregroundColor(Perch.secondary)
                .padding(.horizontal, Perch.s(12))
                .frame(height: Perch.s(24))
                .background(Capsule().fill(Perch.paper))
                .overlay(Capsule().stroke(Perch.chipEdge, lineWidth: 1))
                .perchHover(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Clear the finished run — turns, perches, and clock back to start")
    }
}

/// The dotted arc between the perches, with the courier bead riding it. The
/// bead's move is the panel's signature motion: it hops the arc on every
/// handoff with a little spring, the one playful gesture in an otherwise
/// native panel.
struct PerchFlightPath: View {
    /// Where the bead sits along the arc, 0 at ChatGPT's end, 1 at Claude's.
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                arc(width: width)
                    .stroke(Perch.path,
                            style: StrokeStyle(lineWidth: Perch.s(2),
                                               lineCap: .round,
                                               dash: [1, Perch.s(6)]))
                Circle()
                    .fill(Perch.amber)
                    .frame(width: Perch.s(10), height: Perch.s(10))
                    .position(point(at: fraction, width: width))
                    .animation(.spring(duration: 0.55, bounce: 0.35), value: fraction)
            }
        }
        .frame(height: Perch.s(44))
    }

    private func arc(width: CGFloat) -> Path {
        Path { p in
            p.move(to: point(at: 0, width: width))
            p.addQuadCurve(to: point(at: 1, width: width),
                           control: control(width: width))
        }
    }

    /// The quadratic arc the stroke draws, evaluated directly so the bead's
    /// position and the path always agree.
    private func point(at t: CGFloat, width: CGFloat) -> CGPoint {
        let p0 = CGPoint(x: Perch.s(6), y: Perch.s(34))
        let p2 = CGPoint(x: width - Perch.s(6), y: Perch.s(34))
        let p1 = control(width: width)
        let mt = 1 - t
        return CGPoint(x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
                       y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y)
    }

    private func control(width: CGFloat) -> CGPoint {
        CGPoint(x: width / 2, y: Perch.s(2))
    }
}

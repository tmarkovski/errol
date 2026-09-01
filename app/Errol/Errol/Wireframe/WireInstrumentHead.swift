// The head unit: the two participant cards, the route between them, and
// the center deck's counter and status plates. The one row that stays on
// screen in both the full console and the compact panel, and the busiest
// file in the skin. See WireframePanelView for the skin.

import SwiftUI

/// Both participant cards, the route with its courier, the status plates,
/// and the odometer. One view on purpose: everything here depends on the
/// same relay-state cluster, so splitting it further would add plumbing
/// without separating meaningful updates.
struct WireInstrumentHead: View {
    let controller: RelayController

    var body: some View {
        HStack(alignment: .top, spacing: Wire.s(14)) {
            participant(.chatgpt, status: controller.chatgptStatus,
                        conversation: controller.chatgptConversation)
            centerDeck
            participant(.claude, status: controller.claudeStatus,
                        conversation: controller.claudeConversation)
        }
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var bothEnded: Bool {
        controller.chatgptConversation == .ended && controller.claudeConversation == .ended
    }

    // MARK: The participant cards

    private func participant(_ speaker: Speaker, status: SideStatus,
                             conversation: ConversationStatus) -> some View {
        VStack(spacing: Wire.s(8)) {
            WireGauge(level: gaugeLevel(conversation),
                      driven: conversation == .chatting)
            // The nameplate: who this is and what it is showing, then the
            // model behind it — identity in two rows, state in the
            // instruments below. Both rows reserve their height whatever is
            // missing, so the lamps sit level on both cards.
            VStack(spacing: Wire.s(2)) {
                nameplate(status)
                let detail = detailRow(status)
                Text(detail.text)
                    .foregroundColor(detail.diagnosis ? Wire.ink.opacity(0.75)
                                                      : Wire.faint)
            }
            .font(Wire.mono(8.5))
            .lineLimit(1)
            .truncationMode(.tail)
            // Half the card each, lamp centered in its half. Spacing the pair
            // by their own edges instead would hang the bezels off however
            // long the nameplates happen to be, and a renamed lamp would
            // shift both; halves are fixed, so the text underneath can say
            // anything. The negative inset cancels the card's padding for
            // this row alone, because the halves worth dividing are the drawn
            // card's, not the padded content box's.
            HStack(spacing: 0) {
                WireSignalLamp(label: readyLabel(status.state),
                               lens: readyLens(status.state))
                    .frame(maxWidth: .infinity)
                WireSignalLamp(label: "THINK",
                               lens: conversation == .chatting ? .orange : nil,
                               pulsing: conversation == .chatting)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, -Wire.s(10))
            // The states with no lamp of their own: a held reply, captured
            // but undelivered (in an uninterrupted run a side is never seen
            // in .replied), and the side's own sign-off, which a SEAL
            // indicator used to mark. Blank otherwise, height held.
            Text(footnote(conversation))
                .foregroundColor(Wire.ink.opacity(0.75))
                .font(Wire.mono(8.5))
                .lineLimit(1)
        }
        .padding(Wire.s(10))
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Wire.boxCorner).fill(Wire.well))
        .overlay(cardStroke(for: speaker, conversation: conversation))
        // Clicking a card nominates that side to open the next run — the
        // largest target for the plainest statement of it. The courier's
        // pointer swinging over is the acknowledgement.
        .contentShape(Rectangle())
        .onTapGesture { nominate(speaker) }
        .modifier(WireHandCursor(active: canChooseOpener))
        .help(canChooseOpener ? "Have \(status.appName) send the opening message" : "")
    }

    /// The name, and beside it the surface that side is showing — the app's
    /// own mode word ("Chat", "Cowork", "Code"), kept muted and a size down
    /// so the pair reads as a name wearing a label rather than as two
    /// labels. It rides the name's line instead of taking a row under it
    /// because a mode belongs to the thing it is a mode of, and because the
    /// row it gives back is a row the card was spending on a single word.
    ///
    /// The mode is the one part of the nameplate that arrives from a sweep
    /// rather than from the layout, so it is animated in. The pair is
    /// centered, so a mode widening from nothing walks the name off center
    /// and itself out from behind it; a word that blinked into place would
    /// read as a glitch on a panel where nothing else appears unasked. The
    /// same animation covers a mode that changes — the word cross-fades
    /// while the name slides over to make room — and one that goes away,
    /// which is the arrival run backwards.
    private func nameplate(_ status: SideStatus) -> some View {
        let mode = status.surface ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(status.appName.uppercased())
                .font(Wire.mono(10, .bold))
                .foregroundColor(Wire.ink)
                // Who the card is never truncates. A side with no chat
                // window reports its open surfaces here as one joined
                // string, which is the one mode long enough to crowd the
                // name off its own plate; the priority spends that overflow
                // on the mode's tail instead.
                .layoutPriority(1)
            Text(mode)
                .foregroundColor(Wire.faint)
                // The gutter belongs to the mode rather than to the stack:
                // an HStack's own spacing would sit there holding the name
                // off center on a card that has no mode to show.
                .padding(.leading, mode.isEmpty ? 0 : Wire.s(4))
            // The mode's line, with none of its width. A row measured from
            // the name alone stands a point shorter than one carrying a
            // mode, so a card still waiting on its first sweep would sit
            // its lamps a point off the other card's, and the mode's
            // arrival would land with a hop. The strut holds that point
            // open from the start and costs no centering to do it.
            Text(" ").frame(width: 0)
        }
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: mode)
    }

    /// The border tells the card's place in the turn. Waiting its turn, it
    /// speaks the dash grammar the rail and the ghost stop already use —
    /// dashed ink while the side's turn is on its way, the plain faint
    /// outline when the next message is none of its business — and the
    /// dashes hold still on purpose, since marching ones read as a
    /// selection rather than a state. Composing, the outline stops being a
    /// line and becomes the speaker it is driving (WireSpeakerBorder): the
    /// one card doing work is the one card moving, which is a thing the eye
    /// finds without being asked to compare anything.
    @ViewBuilder
    private func cardStroke(for speaker: Speaker,
                            conversation: ConversationStatus) -> some View {
        if conversation == .chatting {
            WireSpeakerBorder()
        } else {
            let upNext = nextTaker == speaker
            RoundedRectangle(cornerRadius: Wire.boxCorner)
                .stroke(upNext ? Wire.ink : Wire.faint.opacity(0.5),
                        style: StrokeStyle(lineWidth: Wire.s(1),
                                           dash: upNext ? [Wire.s(2.5), Wire.s(2.5)] : []))
        }
    }

    /// The readiness lamp's nameplate reads out the state rather than naming
    /// the instrument, because a red lamp under the word READY says the
    /// opposite of what it means at a glance. The lens is what the eye
    /// catches first; this is what settles it.
    private func readyLabel(_ state: ReadyState) -> String {
        switch state {
        case .ready: "READY"
        case .checking: "CHECKING"
        case .notReady, .missing: "NOT READY"
        }
    }

    /// Green when the side is relayable, red when it is not, amber while the
    /// first sweep is still out. The readiness lamp is never dark — an unlit
    /// one would read as "no signal" rather than "not ready".
    private func readyLens(_ state: ReadyState) -> WireLens {
        switch state {
        case .ready: .green
        case .checking: .amber
        case .notReady, .missing: .red
        }
    }

    /// The line under the lamps (see its call site for why these two states
    /// live in words rather than in a lamp).
    private func footnote(_ conversation: ConversationStatus) -> String {
        switch conversation {
        case .replied: conversation.rawValue
        case .ended: "Signed off"
        default: " "
        }
    }

    /// Where the needle rests. Composing, it is also knocked about that
    /// rest by the beat its own card's border is playing, so the gauge
    /// carries the working state on its own rather than only agreeing with
    /// the outline around it.
    private func gaugeLevel(_ conversation: ConversationStatus) -> Double {
        switch conversation {
        case .chatting: 0.72
        // A held reply drops the needle the same way waiting does: the side
        // is in the conversation but not working.
        case .waiting, .replied: 0.28
        case .ended, .notStarted: 0.08
        }
    }

    /// The row under the nameplate: model and effort as one plate ("5.6 Sol
    /// High", "Fable 5 Extra"). The separator Readiness composes is for the
    /// skins that join surface and model on a single line; here the surface
    /// has gone up to sit beside the name, so the model has the row to
    /// itself.
    ///
    /// It gives that row over to the diagnosis while the side is not
    /// relayable: a red lens conflates four failures whose remedies differ
    /// — launch the app, open a chat window, grant Accessibility — and a
    /// side in that state has no model to name anyway. The isRunning guard
    /// keeps a stale diagnosis off a card mid-run, when the readiness
    /// scanner is paused. A space when there is neither, so the row holds
    /// its height.
    private func detailRow(_ status: SideStatus) -> (text: String, diagnosis: Bool) {
        if !controller.isRunning,
           status.state == .notReady || status.state == .missing {
            return (status.headline, true)
        }
        return (status.model?.replacingOccurrences(of: " \u{00B7} ", with: " ") ?? " ", false)
    }

    // MARK: The center deck and the route between the cards

    private var centerDeck: some View {
        VStack(spacing: Wire.s(8)) {
            // Named under the drums the way the lamps are named under
            // their lenses, in the same plate style.
            VStack(spacing: Wire.s(3)) {
                WireOdometer(value: controller.currentTurn)
                Text("TURN")
                    .font(Wire.mono(7, .bold))
                    .tracking(0.5)
                    .foregroundColor(Wire.faint)
            }
            route
            Text(primaryStatus.uppercased())
                .font(Wire.mono(8, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .lineLimit(1)
                .fixedSize()
            secondaryStatus
        }
        .frame(width: Wire.s(150))
    }

    /// The line under the primary status: a single faint readout in one
    /// style, whichever state fills it in. In a run it
    /// reports a pause — the word alone tells PAUSING from PAUSED, and the
    /// ghost stop draws that distinction on the route besides. Idle it
    /// names the side the courier is aimed at, since an arrow's angle is
    /// not something the panel should make anyone read. Blank otherwise,
    /// so the row's height never moves.
    ///
    /// Plain faint text, not a control: flipping the opener already lives
    /// on the participant cards and on the courier itself, and brackets
    /// are what this panel puts around a choice — a readout gets none.
    private var secondaryStatus: some View {
        Text(controller.isRunning
                ? (controller.isHolding ? "PAUSED" : "PAUSING")
                : "\(openerName.uppercased()) OPENS")
            .font(Wire.mono(8, .bold))
            .tracking(0.5)
            .foregroundColor(Wire.faint)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, Wire.s(2))
            .opacity(controller.isRunning && !controller.isPaused ? 0 : 1)
    }

    private var primaryStatus: String {
        if controller.isRunning {
            if controller.isHolding { return "Holding at handoff" }
            if controller.chatgptConversation == .chatting { return "ChatGPT is composing" }
            if controller.claudeConversation == .chatting { return "Claude is composing" }
            return "Relaying"
        }
        if bothEnded { return "Run complete" }
        if bothReady { return "Ready" }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) { return "Scanning" }
        return "Waiting on apps"
    }

    /// The route as a plain line — dashed while idle, solid in a run — with
    /// the courier riding it: an open bead that slides over to park beside
    /// whoever is composing, and a pointer swinging out of the bead toward
    /// the side the next message is bound for.
    private var route: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let inset = Wire.s(6)
            ZStack {
                rail(width: geo.size.width, midY: midY)
                ghostStop
                    .position(x: geo.size.width / 2, y: midY)
                    .opacity(showsGhostStop ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showsGhostStop)
                WireCourier(pointsRight: pointsRight,
                            showsPointer: routeIsLive,
                            interactive: canChooseOpener,
                            onFlip: flipOpener,
                            onRoulette: { controller.firstSpeaker = $0 })
                    .position(x: inset + courierFraction * (geo.size.width - 2 * inset),
                              y: midY)
                    .animation(.easeInOut(duration: 0.45), value: courierFraction)
            }
        }
        // Tall enough for the pointer's swing between the two sides to stay
        // inside the deck; the center column is still the shortest of the
        // three, so the head unit does not grow for it.
        .frame(height: Wire.s(36))
    }

    private func rail(width: CGFloat, midY: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: Wire.s(2), y: midY))
            p.addLine(to: CGPoint(x: width - Wire.s(2), y: midY))
        }
        .stroke(Wire.faint,
                style: StrokeStyle(lineWidth: Wire.s(1.5), lineJoin: .round,
                                   dash: controller.isRunning ? [] : [Wire.s(3), Wire.s(3)]))
    }

    /// The spot the courier will come to rest on, drawn only while a pause is
    /// on its way: dashed and muted, because a pause asked for mid-reply is
    /// not in effect yet — the agent is still writing, and the run carries on
    /// until it reaches the handoff.
    private var ghostStop: some View {
        Circle()
            .stroke(Wire.faint,
                    style: StrokeStyle(lineWidth: Wire.s(1.5),
                                       dash: [Wire.s(2.5), Wire.s(2.5)]))
            .frame(width: Wire.s(10), height: Wire.s(10))
    }

    /// Only in the gap between asking for a pause and the run taking it. Once
    /// the courier is standing there the mark has nothing left to say.
    private var showsGhostStop: Bool {
        controller.isPaused && !controller.isHolding
    }

    /// The bead parks beside whoever holds the message and waits in the
    /// middle when nobody does: before the run opens, after it closes, and
    /// once a pause has actually parked a captured reply there.
    private var courierFraction: CGFloat {
        if controller.isHolding { return 0.5 }
        if controller.chatgptConversation == .chatting { return 0.04 }
        if controller.claudeConversation == .chatting { return 0.96 }
        return 0.5
    }

    /// The pointer names the side the next message is bound for: away from
    /// whoever is composing now, and — with nobody composing — at whichever
    /// side is nominated to open.
    private var pointsRight: Bool {
        if holdsTheMessage(controller.chatgptConversation) { return true }
        if holdsTheMessage(controller.claudeConversation) { return false }
        return controller.firstSpeaker == .claude
    }

    /// Whether the next message is coming from this side: it is writing one,
    /// or it has written one that has not been delivered yet. Either way the
    /// pointer belongs on the far side.
    private func holdsTheMessage(_ status: ConversationStatus) -> Bool {
        status == .chatting || status == .replied
    }

    /// Every state has a next message except one: a finished run still on
    /// screen, both sides signed off. Once it lets go of the panel the
    /// pointer means the next run's opener again.
    private var routeIsLive: Bool { !(controller.isRunning && bothEnded) }

    /// The side that composes the next message: the far side of whoever
    /// holds one, or the nominated opener. Nil while a finished run is
    /// still on screen, and nil the moment a pause is asked for — from
    /// then on the next actor is the human, which the ghost stop and the
    /// parked courier already say, and no card's turn is on its way.
    private var nextTaker: Speaker? {
        guard routeIsLive, !controller.isPaused else { return nil }
        return pointsRight ? .claude : .chatgpt
    }

    // MARK: Nominating an opener

    /// Aiming the courier only means something before a run. Once the relay
    /// is going the message the pointer names is already written — paused, it
    /// is captured and waiting — and there is only one place it can go.
    private var canChooseOpener: Bool { !controller.isRunning }

    private func nominate(_ speaker: Speaker) {
        guard canChooseOpener else { return }
        controller.firstSpeaker = speaker
    }

    private func flipOpener() {
        nominate(controller.firstSpeaker == .chatgpt ? .claude : .chatgpt)
    }

    /// The nominated side, named the way its own card names it.
    private var openerName: String {
        switch controller.firstSpeaker {
        case .chatgpt: controller.chatgptStatus.appName
        case .claude: controller.claudeStatus.appName
        }
    }
}

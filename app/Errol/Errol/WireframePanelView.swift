// The wireframe instrument skin (see PanelRootView for skin selection):
// DesignMockups' Option A made real. The study's rule carries over as the
// design itself — every state is legible from lamps, needles, counters,
// and labels alone; four grays, no glow, no chassis color. The exceptions
// are the two signal lamps in the old machine-panel idiom — RDY burning
// red, amber, or green, and THINK an orange bulb breathing while a side
// composes; everything they say is still said in words on the line below
// them, so the rule holds. The panel window is borderless
// (MenuBarController), so the paper card this view paints is the panel's
// own edge.
//
// Idle, the full console shows the instrument head, the conversation
// setup, run options, and the log. Starting a run shrinks the panel to
// the head unit alone (controller.compact drives the AppKit frame change;
// PanelLayout has the sizes). EXPAND brings the full console back mid-run
// with the setup rows disabled.

import SwiftUI

// MARK: - Palette

/// The skin draws from four grays, plus the lens colors the two signal
/// lamps burn — the muted red, jade green, and orange of old equipment
/// panels rather than screen primaries.
private enum Wire {
    static let ink = Color(white: 0.20)
    static let faint = Color(white: 0.52)
    static let paper = Color(white: 0.94)
    static let well = Color(white: 0.885)

    /// Every length and type size on the card is a study measurement put
    /// through `s`, so this one number sets how large the instrument reads.
    /// The study drew at 1.0 and came out cramped on a laptop display.
    static let scale: CGFloat = 1.2
    static func s(_ points: CGFloat) -> CGFloat { points * scale }
    /// Instrument type: monospaced, scaled with everything else.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .monospaced)
    }
    /// The few proportional strings — what a person types, and the topic.
    static func text(_ size: CGFloat) -> Font { .system(size: s(size)) }

    /// The fixed card size; the panel adds the outer padding. Expanded, the
    /// card height is pinned and the log absorbs the difference between the
    /// topic field and the taller custom-instructions editor; compact, the
    /// card hugs the head unit.
    static let cardWidth = s(480)
    static let expandedCardHeight = s(560)
    /// The shadow's room around the card, a side.
    static let cardMargin = s(14)
}

/// The window frames the skin needs, derived from the card itself so the
/// panel grows with `Wire.scale` instead of drifting from it. PanelLayout
/// hands these straight through. The compact card is content-sized, so its
/// height carries slack.
enum WireframeMetrics {
    static let expandedPanel = CGSize(width: Wire.cardWidth + 2 * Wire.cardMargin,
                                      height: Wire.expandedCardHeight + 2 * Wire.cardMargin)
    static let compactPanel = CGSize(width: expandedPanel.width, height: Wire.s(252))
}

// MARK: - Instrument parts

/// A half-circle gauge; the needle rises while that side is composing.
private struct WireGauge: View {
    var level: Double

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height - Wire.s(3))
            let r = min(sz.width / 2 - Wire.s(4), sz.height - Wire.s(8))
            var arc = Path()
            arc.addArc(center: c, radius: r,
                       startAngle: .degrees(180), endAngle: .degrees(360),
                       clockwise: false)
            ctx.stroke(arc, with: .color(Wire.faint),
                       style: StrokeStyle(lineWidth: Wire.s(3), lineCap: .round))
            for i in 0...4 {
                let a = Angle.degrees(180 + Double(i) * 45).radians
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(6)),
                                      y: c.y + sin(a) * (r - Wire.s(6))))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(2)),
                                         y: c.y + sin(a) * (r - Wire.s(2))))
                ctx.stroke(tick, with: .color(Wire.faint.opacity(0.7)), lineWidth: Wire.s(1))
            }
            let a = Angle.degrees(180 + 180 * min(max(level, 0), 1)).radians
            var hand = Path()
            hand.move(to: c)
            hand.addLine(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(8)),
                                     y: c.y + sin(a) * (r - Wire.s(8))))
            ctx.stroke(hand, with: .color(Wire.ink),
                       style: StrokeStyle(lineWidth: Wire.s(2), lineCap: .round))
            let hub = Wire.s(6)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - hub / 2, y: c.y - hub / 2,
                                            width: hub, height: hub)),
                     with: .color(Wire.ink))
        }
        .frame(width: Wire.s(54), height: Wire.s(32))
    }
}

/// A colored bulb behind glass: a bright filament core inside deeper glass,
/// or the cloudy tint of the same lens with nothing lit behind it.
private struct WireLens {
    var core: Color
    var glass: Color

    static let green = WireLens(core: Color(red: 0.60, green: 0.92, blue: 0.53),
                                glass: Color(red: 0.11, green: 0.42, blue: 0.19))
    static let amber = WireLens(core: Color(red: 0.99, green: 0.80, blue: 0.38),
                                glass: Color(red: 0.54, green: 0.33, blue: 0.04))
    static let red = WireLens(core: Color(red: 0.97, green: 0.42, blue: 0.26),
                              glass: Color(red: 0.51, green: 0.09, blue: 0.06))
    static let orange = WireLens(core: Color(red: 1.00, green: 0.78, blue: 0.30),
                                 glass: Color(red: 0.72, green: 0.37, blue: 0.02))
}

/// A signal lamp: a glass lens in a metal bezel, or — with no lens — the
/// plain dark-ringed dot the gray lamps show when off, since a tinted unlit
/// lens reads as a third state rather than as nothing. `pulsing` gives it
/// the slow breathing fade of a lamp wired to something still working, so
/// THINK reads as activity rather than as one more steady state.
private struct WireSignalLamp: View {
    var label: String
    var lens: WireLens?
    var pulsing = false

    @State private var dimmed = false

    /// Filament off-center, the way a bulb sits behind its lens.
    private var glass: AnyShapeStyle {
        guard let lens else { return AnyShapeStyle(Wire.paper) }
        return AnyShapeStyle(RadialGradient(colors: [lens.core, lens.glass],
                                           center: UnitPoint(x: 0.36, y: 0.32),
                                           startRadius: 0, endRadius: Wire.s(7)))
    }

    var body: some View {
        VStack(spacing: Wire.s(3)) {
            Circle()
                .fill(glass)
                .opacity(dimmed ? 0.32 : 1)
                .overlay(Circle().stroke(lens == nil ? Wire.faint.opacity(0.35)
                                                     : Wire.ink.opacity(0.55),
                                         lineWidth: Wire.s(1)))
                .frame(width: Wire.s(9), height: Wire.s(9))
                .shadow(color: (lens?.glass ?? .clear).opacity(dimmed ? 0.15 : 0.55),
                        radius: Wire.s(2.5))
            Text(label)
                .font(Wire.mono(7, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.faint)
        }
        // initial: true starts the fade on a lamp that is already lit when
        // the panel opens mid-run, not only on the transition into one.
        .onChange(of: pulsing, initial: true) { _, on in
            dimmed = false
            guard on else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }
}

/// Boxed rolling digits: the turn counter.
private struct WireOdometer: View {
    var value: Int
    var digits = 2

    var body: some View {
        HStack(spacing: Wire.s(2)) {
            let padded = String(format: "%0\(digits)d", value)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, ch in
                WireDigitWheel(digit: ch)
            }
        }
    }
}

/// One counter wheel. A changed digit rolls up out of its window while the
/// next rolls in underneath, the way the drums in a mechanical counter turn.
/// Drums only turn one way, so a count that jumps backward — a new run
/// resetting to zero — rolls upward too rather than running in reverse.
private struct WireDigitWheel: View {
    var digit: Character

    private var window: RoundedRectangle { RoundedRectangle(cornerRadius: Wire.s(3)) }

    var body: some View {
        ZStack {
            Text(String(digit))
                .font(Wire.mono(13, .bold))
                .foregroundColor(Wire.paper)
                // A full-box frame makes the slide a whole drum face, so the
                // outgoing digit is gone before the incoming one appears.
                .frame(width: Wire.s(16), height: Wire.s(21))
                .id(digit)
                .transition(.asymmetric(insertion: .move(edge: .bottom),
                                        removal: .move(edge: .top)))
        }
        .frame(width: Wire.s(16), height: Wire.s(21))
        .background(window.fill(Wire.ink))
        .clipShape(window)
        // The drum's seam, which is what makes a counter read as turned
        // rather than typed.
        .overlay(Rectangle().fill(Wire.paper.opacity(0.16)).frame(height: Wire.s(0.5)))
        .animation(.easeInOut(duration: 0.3), value: digit)
    }
}

/// The per-side sign-off indicator: an armed ring that fills when that
/// side ends the conversation.
private struct WireSeal: View {
    var sealed: Bool

    var body: some View {
        VStack(spacing: Wire.s(3)) {
            ZStack {
                Circle()
                    .stroke(Wire.ink.opacity(sealed ? 1 : 0.35), lineWidth: Wire.s(1.5))
                    .frame(width: Wire.s(13), height: Wire.s(13))
                if sealed {
                    Circle().fill(Wire.ink).frame(width: Wire.s(6), height: Wire.s(6))
                }
            }
            .frame(width: Wire.s(14), height: Wire.s(9))
            Text("SEAL")
                .font(Wire.mono(7, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.faint)
        }
    }
}

// MARK: - Skin

struct WireframePanelView: View {
    @ObservedObject var controller: RelayController

    var body: some View {
        VStack(spacing: Wire.s(12)) {
            header
            instrumentRow
            if controller.compact {
                compactFooter
            } else {
                setup
                actionRow
                logWell
            }
        }
        .padding(Wire.s(16))
        .frame(width: Wire.cardWidth,
               height: controller.compact ? nil : Wire.expandedCardHeight)
        .background(
            RoundedRectangle(cornerRadius: Wire.s(10)).fill(Wire.paper)
                .shadow(color: .black.opacity(0.28), radius: Wire.s(9), y: Wire.s(4))
        )
        .overlay(RoundedRectangle(cornerRadius: Wire.s(10)).stroke(Wire.ink.opacity(0.3)))
        .environment(\.colorScheme, .light)
        .padding(Wire.cardMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("ERROL")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            Spacer()
            Text(stateWord)
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.ink)
        }
    }

    private var stateWord: String {
        if controller.isRunning { return controller.isPaused ? "PAUSED" : "IN RUN" }
        if bothEnded { return "DONE" }
        if bothReady { return "READY" }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) { return "CHECKING" }
        return "PREP"
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var bothEnded: Bool {
        controller.chatgptConversation == .ended && controller.claudeConversation == .ended
    }

    // MARK: Instrument head

    private var instrumentRow: some View {
        HStack(alignment: .top, spacing: Wire.s(14)) {
            participant(status: controller.chatgptStatus,
                        conversation: controller.chatgptConversation)
            centerDeck
            participant(status: controller.claudeStatus,
                        conversation: controller.claudeConversation)
        }
    }

    private func participant(status: SideStatus,
                             conversation: ConversationStatus) -> some View {
        VStack(spacing: Wire.s(8)) {
            WireGauge(level: gaugeLevel(conversation))
            Text(status.appName.uppercased())
                .font(Wire.mono(10, .bold))
                .foregroundColor(Wire.ink)
            HStack(spacing: Wire.s(10)) {
                WireSignalLamp(label: "RDY", lens: readyLens(status.state))
                WireSignalLamp(label: "THINK",
                               lens: conversation == .chatting ? .orange : nil,
                               pulsing: conversation == .chatting)
                WireSeal(sealed: conversation == .ended)
            }
            VStack(spacing: Wire.s(2)) {
                Text(primaryLine(status: status, conversation: conversation))
                    .foregroundColor(Wire.ink.opacity(0.75))
                Text(surfaceLine(status))
                    .foregroundColor(Wire.faint)
            }
            .font(Wire.mono(8.5))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(Wire.s(10))
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Wire.s(6)).fill(Wire.well))
        .overlay(RoundedRectangle(cornerRadius: Wire.s(6)).stroke(Wire.faint.opacity(0.5)))
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

    private func gaugeLevel(_ conversation: ConversationStatus) -> Double {
        switch conversation {
        case .chatting: 0.72
        case .waiting: 0.28
        case .ended, .notStarted: 0.08
        }
    }

    /// During a run the readiness scanner is off, so the line switches to
    /// the live conversation state; idle it reports readiness.
    private func primaryLine(status: SideStatus,
                             conversation: ConversationStatus) -> String {
        if controller.isRunning || conversation == .ended {
            return conversation.rawValue
        }
        return status.headline
    }

    /// A single space keeps the row height stable with nothing to show.
    private func surfaceLine(_ status: SideStatus) -> String {
        let line = [status.surface, status.model].compactMap { $0 }
            .joined(separator: " \u{00B7} ")
        return line.isEmpty ? " " : line
    }

    private var centerDeck: some View {
        VStack(spacing: Wire.s(8)) {
            HStack(spacing: Wire.s(4)) {
                Text("TURN")
                    .font(Wire.mono(8, .bold))
                    .foregroundColor(Wire.faint)
                WireOdometer(value: controller.currentTurn)
            }
            route
            Text(statusLine.uppercased())
                .font(Wire.mono(8, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .lineLimit(1)
                .fixedSize()
            Text("PAUSED")
                .font(Wire.mono(8, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .padding(.horizontal, Wire.s(5))
                .padding(.vertical, Wire.s(2))
                .overlay(Rectangle().stroke(Wire.ink, lineWidth: Wire.s(1)))
                .opacity(controller.isPaused ? 1 : 0)
        }
        .frame(width: Wire.s(150))
    }

    private var statusLine: String {
        if controller.isRunning {
            if controller.isPaused { return "Holding at handoff" }
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
                courier
                    .position(x: inset + courierFraction * (geo.size.width - 2 * inset),
                              y: midY)
                    .animation(.easeInOut(duration: 0.45), value: courierFraction)
                    .animation(.easeInOut(duration: 0.45), value: pointsRight)
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

    /// The bead and its pointer. The arm is drawn pointing right and turned
    /// around by rotation, so a handoff reads as one pointer swinging over
    /// rather than as an arrow blinking out on one side and in on the other.
    private var courier: some View {
        ZStack {
            pointer
                .rotationEffect(.degrees(pointsRight ? 0 : 180))
                .opacity(bothEnded ? 0 : 1)
            Circle()
                .fill(Wire.paper)
                .overlay(Circle().stroke(Wire.ink, lineWidth: Wire.s(1.5)))
                .frame(width: Wire.s(10), height: Wire.s(10))
        }
        .frame(width: Wire.s(44), height: Wire.s(36))
    }

    private var pointer: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let style = StrokeStyle(lineWidth: Wire.s(1.5), lineCap: .round, lineJoin: .round)
            var arm = Path()
            arm.move(to: CGPoint(x: c.x + Wire.s(7), y: c.y))
            arm.addLine(to: CGPoint(x: c.x + Wire.s(18), y: c.y))
            ctx.stroke(arm, with: .color(Wire.ink), style: style)
            var head = Path()
            head.move(to: CGPoint(x: c.x + Wire.s(14), y: c.y - Wire.s(4)))
            head.addLine(to: CGPoint(x: c.x + Wire.s(18), y: c.y))
            head.addLine(to: CGPoint(x: c.x + Wire.s(14), y: c.y + Wire.s(4)))
            ctx.stroke(head, with: .color(Wire.ink), style: style)
        }
    }

    /// The bead parks beside whoever holds the message and waits in the
    /// middle when nobody does — before the run opens, and after it closes.
    private var courierFraction: CGFloat {
        if controller.chatgptConversation == .chatting { return 0.04 }
        if controller.claudeConversation == .chatting { return 0.96 }
        return 0.5
    }

    /// The pointer names the side the next message is bound for: away from
    /// whoever is composing now, and — before anyone has spoken — at ChatGPT,
    /// who opens.
    private var pointsRight: Bool {
        controller.chatgptConversation == .chatting
    }

    // MARK: Setup (expanded, idle)

    @ViewBuilder
    private var setup: some View {
        Group {
            shapeRow
            topicInput
            optionsRow
        }
        .disabled(controller.isRunning)
        .opacity(controller.isRunning ? 0.45 : 1)
    }

    private var shapeRow: some View {
        HStack(spacing: Wire.s(8)) {
            Menu {
                ForEach(conversationTemplates) { template in
                    Button(template.name) { controller.conversation = template.name }
                }
                Divider()
                Button(RelayController.customConversation) {
                    controller.conversation = RelayController.customConversation
                }
            } label: {
                Text("[ \(controller.conversation.uppercased()) \u{25BE} ]")
                    .font(Wire.mono(9, .bold))
                    .foregroundColor(Wire.ink)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            if controller.selectedTemplate != nil {
                Button {
                    controller.editInstructions()
                } label: {
                    Text("EDIT INSTRUCTIONS")
                        .font(Wire.mono(8, .bold))
                        .underline()
                        .foregroundColor(Wire.faint)
                }
                .buttonStyle(.plain)
                .help("Show the full opening message this shape composes, and edit it freely")
            }
        }
    }

    @ViewBuilder
    private var topicInput: some View {
        if let template = controller.selectedTemplate {
            TextField(template.topicPrompt, text: $controller.topic, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .lineLimit(1...3)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        } else {
            TextEditor(text: $controller.customInstructions)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .scrollContentBackground(.hidden)
                .frame(height: Wire.s(88))
                .padding(Wire.s(4))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        }
    }

    private var optionsRow: some View {
        HStack(spacing: Wire.s(14)) {
            wireToggle("LIMIT TURNS", isOn: $controller.limitTurns)
                .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
            HStack(spacing: Wire.s(3)) {
                TextField("10", value: $controller.turns, format: .number)
                    .textFieldStyle(.plain)
                    .font(Wire.mono(10))
                    .foregroundColor(Wire.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: Wire.s(26))
                    .padding(.vertical, Wire.s(2))
                    .background(Rectangle().fill(Wire.well))
                    .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                Stepper("", value: $controller.turns, in: 1...99)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .disabled(!controller.limitTurns)
            .opacity(controller.limitTurns ? 1 : 0.45)
            wireToggle("NEW CHATS", isOn: $controller.newChats)
            wireToggle("TILE", isOn: $controller.tileWindows)
                .help("Tile the chat windows side by side when the run starts")
            Spacer(minLength: 0)
        }
    }

    private func wireToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: Wire.s(5)) {
                ZStack {
                    Rectangle()
                        .stroke(Wire.ink, lineWidth: Wire.s(1))
                        .frame(width: Wire.s(10), height: Wire.s(10))
                    if isOn.wrappedValue {
                        Rectangle().fill(Wire.ink).frame(width: Wire.s(5), height: Wire.s(5))
                    }
                }
                Text(label)
                    .font(Wire.mono(8, .bold))
                    .foregroundColor(Wire.ink)
            }
            // A stroked Rectangle only hit-tests along its outline, so an
            // unticked box swallowed clicks aimed straight at it. The whole
            // row — box, gap, and label — is the target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions & log (expanded)

    private var actionRow: some View {
        HStack(spacing: Wire.s(8)) {
            wireButton("INSPECT", disabled: controller.isRunning) {
                controller.runInspect()
            }
            .help("Dump both apps' windows, buttons, and selector matches into the log")
            Spacer()
            if controller.isRunning {
                wireButton("COMPACT", disabled: false) { controller.compact = true }
                    .help("Shrink to the head unit")
                wireButton(controller.isPaused ? "RESUME" : "PAUSE", disabled: false) {
                    controller.togglePause()
                }
                .help(pauseHelp)
            }
            wireButton("RUN", disabled: controller.isRunning || !controller.instructionsReady) {
                controller.start()
            }
            .keyboardShortcut(.defaultAction)
            wireButton("STOP", disabled: !controller.isRunning) { controller.stop() }
        }
    }

    private var pauseHelp: String {
        controller.isPaused
            ? "Send the held reply and continue"
            : "Hold the run at the next handoff"
    }

    private func wireButton(_ label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Wire.mono(9, .bold))
                .foregroundColor(disabled ? Wire.faint : Wire.ink)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(3))
                .overlay(Rectangle().stroke(disabled ? Wire.faint : Wire.ink,
                                            lineWidth: Wire.s(1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var logWell: some View {
        VStack(alignment: .leading, spacing: Wire.s(4)) {
            Text("LOG")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Wire.s(2)) {
                        ForEach(controller.logLines) { line in
                            Text(line.text)
                                .font(Wire.mono(10.5))
                                .foregroundColor(Wire.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Wire.s(8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .onChange(of: controller.logLines.count) { _, _ in
                    if let last = controller.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: Compact footer (in run)

    /// The head unit's bottom row: the loaded shape and topic on the left,
    /// the run controls on the right.
    private var compactFooter: some View {
        HStack(spacing: Wire.s(8)) {
            Text("[ \(controller.conversation.uppercased()) ]")
                .font(Wire.mono(9, .bold))
                .foregroundColor(Wire.ink)
            Text(topicSummary)
                .font(Wire.text(10))
                .foregroundColor(Wire.faint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Wire.s(8))
            wireButton(controller.isPaused ? "RESUME" : "PAUSE", disabled: false) {
                controller.togglePause()
            }
            .help(pauseHelp)
            wireButton("STOP", disabled: false) { controller.stop() }
            wireButton("EXPAND", disabled: false) { controller.compact = false }
                .help("Expand the full console")
        }
    }

    private var topicSummary: String {
        if controller.selectedTemplate == nil {
            return controller.customInstructions
                .components(separatedBy: .newlines).first ?? ""
        }
        return controller.topic
    }
}

// MARK: - Previews

#Preview("Wireframe console (idle)") {
    WireframePanelView(controller: RelayController())
        .background(Color(white: 0.75))
}

#Preview("Wireframe head unit (in run)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.compact = true
    controller.currentTurn = 7
    controller.chatgptConversation = .chatting
    controller.claudeConversation = .waiting
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#if DEBUG
/// The one preview that moves: it hands the conversation back and forth
/// every couple of seconds, so the counter's roll and the pointer's swing
/// play in the canvas while the head unit is being edited. Every other
/// preview here is a frozen state, and a frozen state cannot show an
/// animation that has stopped working.
private struct WireframeHandoffPreview: View {
    @StateObject private var controller: RelayController = {
        let c = RelayController()
        c.isRunning = true
        c.compact = true
        c.currentTurn = 1
        c.conversation = "Debate"
        c.topic = "Are code comments for the why or the what?"
        c.chatgptConversation = .chatting
        c.claudeConversation = .waiting
        return c
    }()

    var body: some View {
        WireframePanelView(controller: controller)
            .background(Color(white: 0.75))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    let claudeSpeaks = controller.chatgptConversation == .chatting
                    controller.chatgptConversation = claudeSpeaks ? .waiting : .chatting
                    controller.claudeConversation = claudeSpeaks ? .chatting : .waiting
                    controller.currentTurn += 1
                }
            }
    }
}

#Preview("Wireframe handoff (animated)") {
    WireframeHandoffPreview()
}
#endif

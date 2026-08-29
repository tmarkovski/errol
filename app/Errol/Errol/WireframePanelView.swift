// The wireframe instrument skin (see PanelRootView for skin selection):
// DesignMockups' Option A made real. The study's rule carries over as the
// design itself — every state is legible from lamps, needles, counters,
// and labels alone; four grays, no glow, no chassis color. The panel
// window is borderless (MenuBarController), so the paper card this view
// paints is the panel's own edge.
//
// Idle, the full console shows the instrument head, the conversation
// setup, run options, and the log. Starting a run shrinks the panel to
// the head unit alone (controller.compact drives the AppKit frame change;
// PanelLayout has the sizes). EXPAND brings the full console back mid-run
// with the setup rows disabled.

import SwiftUI

// MARK: - Palette

/// The whole skin draws from four grays; color never carries a state.
private enum Wire {
    static let ink = Color(white: 0.20)
    static let faint = Color(white: 0.52)
    static let paper = Color(white: 0.94)
    static let well = Color(white: 0.885)

    /// The fixed card size; PanelLayout adds the outer padding. Expanded,
    /// the card height is pinned and the log absorbs the difference between
    /// the topic field and the taller custom-instructions editor; compact,
    /// the card hugs the head unit.
    static let cardWidth: CGFloat = 480
    static let expandedCardHeight: CGFloat = 560
}

// MARK: - Instrument parts

/// A half-circle gauge; the needle rises while that side is composing.
private struct WireGauge: View {
    var level: Double

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height - 3)
            let r = min(sz.width / 2 - 4, sz.height - 8)
            var arc = Path()
            arc.addArc(center: c, radius: r,
                       startAngle: .degrees(180), endAngle: .degrees(360),
                       clockwise: false)
            ctx.stroke(arc, with: .color(Wire.faint),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for i in 0...4 {
                let a = Angle.degrees(180 + Double(i) * 45).radians
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * (r - 6), y: c.y + sin(a) * (r - 6)))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * (r - 2), y: c.y + sin(a) * (r - 2)))
                ctx.stroke(tick, with: .color(Wire.faint.opacity(0.7)), lineWidth: 1)
            }
            let a = Angle.degrees(180 + 180 * min(max(level, 0), 1)).radians
            var hand = Path()
            hand.move(to: c)
            hand.addLine(to: CGPoint(x: c.x + cos(a) * (r - 8), y: c.y + sin(a) * (r - 8)))
            ctx.stroke(hand, with: .color(Wire.ink),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                     with: .color(Wire.ink))
        }
        .frame(width: 54, height: 32)
    }
}

/// A labeled indicator lamp; off is a visible state, not an absence.
private struct WireLamp: View {
    var label: String
    var on: Bool

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(on ? Wire.ink : Wire.paper)
                .overlay(Circle().stroke(Wire.faint.opacity(0.35), lineWidth: 1))
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Wire.faint)
        }
    }
}

/// Boxed rolling digits: the turn counter.
private struct WireOdometer: View {
    var value: Int
    var digits = 2

    var body: some View {
        HStack(spacing: 2) {
            let padded = String(format: "%0\(digits)d", value)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Wire.paper)
                    .frame(width: 16, height: 21)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Wire.ink))
            }
        }
    }
}

/// The per-side sign-off indicator: an armed ring that fills when that
/// side ends the conversation.
private struct WireSeal: View {
    var sealed: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Wire.ink.opacity(sealed ? 1 : 0.35), lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                if sealed {
                    Circle().fill(Wire.ink).frame(width: 6, height: 6)
                }
            }
            .frame(width: 14, height: 9)
            Text("SEAL")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Wire.faint)
        }
    }
}

// MARK: - Skin

struct WireframePanelView: View {
    @ObservedObject var controller: RelayController

    var body: some View {
        VStack(spacing: 12) {
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
        .padding(16)
        .frame(width: Wire.cardWidth,
               height: controller.compact ? nil : Wire.expandedCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Wire.paper)
                .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Wire.ink.opacity(0.3)))
        .environment(\.colorScheme, .light)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("ERROL")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            Spacer()
            Text(stateWord)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
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
        HStack(alignment: .top, spacing: 14) {
            participant(status: controller.chatgptStatus,
                        conversation: controller.chatgptConversation)
            centerDeck
            participant(status: controller.claudeStatus,
                        conversation: controller.claudeConversation)
        }
    }

    private func participant(status: SideStatus,
                             conversation: ConversationStatus) -> some View {
        VStack(spacing: 8) {
            WireGauge(level: gaugeLevel(conversation))
            Text(status.appName.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Wire.ink)
            HStack(spacing: 10) {
                WireLamp(label: "RDY", on: status.state == .ready)
                WireLamp(label: "THINK", on: conversation == .chatting)
                WireLamp(label: "ARMED", on: conversation == .waiting)
                WireSeal(sealed: conversation == .ended)
            }
            VStack(spacing: 2) {
                Text(primaryLine(status: status, conversation: conversation))
                    .foregroundColor(Wire.ink.opacity(0.75))
                Text(surfaceLine(status))
                    .foregroundColor(Wire.faint)
            }
            .font(.system(size: 8.5, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Wire.well))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Wire.faint.opacity(0.5)))
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
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("TURN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Wire.faint)
                WireOdometer(value: controller.currentTurn)
            }
            route
            Text(statusLine.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .lineLimit(1)
                .fixedSize()
            Text("PAUSED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(Wire.ink, lineWidth: 1))
                .opacity(controller.isPaused ? 1 : 0)
        }
        .frame(width: 150)
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

    /// The route as a plain line: dashed while idle, solid in a run, with a
    /// chevron pointing at the side the next delivery goes to and the
    /// courier as an open circle parked by whoever holds the message.
    private var route: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 2, y: midY))
            line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            ctx.stroke(line, with: .color(Wire.faint),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round,
                                          dash: controller.isRunning ? [] : [3, 3]))
            if controller.isRunning, !controller.isPaused {
                if controller.chatgptConversation == .chatting {
                    var chevron = Path()
                    let cx = size.width - 12
                    chevron.move(to: CGPoint(x: cx - 4, y: midY - 4))
                    chevron.addLine(to: CGPoint(x: cx, y: midY))
                    chevron.addLine(to: CGPoint(x: cx - 4, y: midY + 4))
                    ctx.stroke(chevron, with: .color(Wire.ink), lineWidth: 1.5)
                } else if controller.claudeConversation == .chatting {
                    var chevron = Path()
                    let cx: CGFloat = 12
                    chevron.move(to: CGPoint(x: cx + 4, y: midY - 4))
                    chevron.addLine(to: CGPoint(x: cx, y: midY))
                    chevron.addLine(to: CGPoint(x: cx + 4, y: midY + 4))
                    ctx.stroke(chevron, with: .color(Wire.ink), lineWidth: 1.5)
                }
            }
            let cx = 6 + courierFraction * (size.width - 12)
            let dot = CGRect(x: cx - 5, y: midY - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: dot), with: .color(Wire.paper))
            ctx.stroke(Path(ellipseIn: dot), with: .color(Wire.ink), lineWidth: 1.5)
        }
        .frame(height: 22)
    }

    private var courierFraction: CGFloat {
        if controller.chatgptConversation == .chatting { return 0.04 }
        if controller.claudeConversation == .chatting { return 0.96 }
        if bothEnded || controller.isRunning { return 0.5 }
        return 0.04
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
        HStack(spacing: 8) {
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                .font(.system(size: 11))
                .foregroundColor(Wire.ink)
                .lineLimit(1...3)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        } else {
            TextEditor(text: $controller.customInstructions)
                .font(.system(size: 11))
                .foregroundColor(Wire.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 88)
                .padding(4)
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        }
    }

    private var optionsRow: some View {
        HStack(spacing: 14) {
            wireToggle("LIMIT TURNS", isOn: $controller.limitTurns)
                .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
            HStack(spacing: 3) {
                TextField("10", value: $controller.turns, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Wire.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 26)
                    .padding(.vertical, 2)
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
            HStack(spacing: 5) {
                ZStack {
                    Rectangle()
                        .stroke(Wire.ink, lineWidth: 1)
                        .frame(width: 10, height: 10)
                    if isOn.wrappedValue {
                        Rectangle().fill(Wire.ink).frame(width: 5, height: 5)
                    }
                }
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Wire.ink)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions & log (expanded)

    private var actionRow: some View {
        HStack(spacing: 8) {
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(disabled ? Wire.faint : Wire.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(disabled ? Wire.faint : Wire.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var logWell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LOG")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.logLines) { line in
                            Text(line.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Wire.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
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
        HStack(spacing: 8) {
            Text("[ \(controller.conversation.uppercased()) ]")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Wire.ink)
            Text(topicSummary)
                .font(.system(size: 10))
                .foregroundColor(Wire.faint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
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

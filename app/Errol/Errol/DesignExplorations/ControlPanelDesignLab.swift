// A disconnected SwiftUI design lab for Errol's compact control surface.
// These studies use local preview state only and can be deleted without
// affecting RelayController or the running app.

#if DEBUG

import SwiftUI

struct ControlPanelDesignLab: View {
    @State private var concept: LabConcept
    @State private var phase: LabPhase
    @State private var topic = "Find the strongest counterargument to our launch plan"

    init(initialConcept: Int = 0, initialPhase: Int = 2) {
        let concepts = LabConcept.allCases
        let phases = LabPhase.allCases
        let conceptIndex = min(max(initialConcept, 0), concepts.count - 1)
        let phaseIndex = min(max(initialPhase, 0), phases.count - 1)
        _concept = State(initialValue: concepts[conceptIndex])
        _phase = State(initialValue: phases[phaseIndex])
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Group {
                switch concept {
                case .dispatch:
                    DispatchDeskMock(topic: $topic, phase: $phase)
                case .tapeLoop:
                    TapeLoopMock(topic: $topic, phase: $phase)
                case .patchBay:
                    PatchBayMock(topic: $topic, phase: $phase)
                }
            }
            .id(concept)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

            VStack(spacing: 9) {
                Picker("Concept", selection: $concept) {
                    ForEach(LabConcept.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 500)

                HStack(spacing: 8) {
                    ForEach(LabPhase.allCases) { item in
                        Button(item.rawValue) {
                            phase = item
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: phase == item ? .semibold : .regular))
                        .foregroundStyle(phase == item ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(phase == item ? Color.primary.opacity(0.09) : .clear)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .frame(width: 880, height: 650)
        .background(LabColor.stage)
        .animation(.easeInOut(duration: 0.18), value: concept)
    }
}

private enum LabConcept: String, CaseIterable, Identifiable {
    case dispatch = "A · Dispatch desk"
    case tapeLoop = "B · Tape loop"
    case patchBay = "C · Patch bay"

    var id: Self { self }
}

private enum LabPhase: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case thinking = "Thinking"
    case handoff = "Handoff"
    case complete = "Complete"

    var id: Self { self }
    var isRunning: Bool { self == .thinking || self == .handoff }

    var fraction: CGFloat {
        switch self {
        case .ready, .thinking: 0.08
        case .handoff: 0.52
        case .complete: 0.92
        }
    }

    var status: String {
        switch self {
        case .ready: "Cleared for dispatch"
        case .thinking: "Codex is composing"
        case .handoff: "Errol is carrying turn 07"
        case .complete: "Conversation delivered"
        }
    }
}

// MARK: - A · Dispatch desk

/// A tiny postal sorting desk: the conversation is a consignment, Errol is
/// the courier, and the run begins by physically dispatching the topic card.
private struct DispatchDeskMock: View {
    @Binding var topic: String
    @Binding var phase: LabPhase
    @State private var mode = "Critique"
    @State private var freshChats = true
    @State private var turns = 10

    private let paper = Color(red: 0.96, green: 0.91, blue: 0.79)
    private let paperEdge = Color(red: 0.67, green: 0.54, blue: 0.35)
    private let ink = Color(red: 0.13, green: 0.18, blue: 0.25)
    private let blue = Color(red: 0.15, green: 0.39, blue: 0.68)
    private let coral = Color(red: 0.84, green: 0.33, blue: 0.25)
    private let shell = Color(red: 0.80, green: 0.75, blue: 0.64)

    var body: some View {
        VStack(spacing: 13) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 12))
                    Text("ERROL DISPATCH")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.8)
                }
                Spacer()
                DispatchLamp(label: "CODEX", color: blue, lit: phase == .thinking)
                DispatchLamp(label: "IN FLIGHT", color: coral, lit: phase == .handoff)
                DispatchLamp(label: "CLAUDE", color: coral, lit: phase == .complete)
            }

            HStack(spacing: 12) {
                DispatchStation(name: "CODEX", monogram: "C", color: blue,
                                detail: phase == .thinking ? "COMPOSING" : "READY")

                DispatchRoute(phase: phase, ink: ink, blue: blue, coral: coral)
                    .frame(maxWidth: .infinity)

                DispatchStation(name: "CLAUDE", monogram: "A", color: coral,
                                detail: phase == .complete ? "SIGNED" : "READY")
            }
            .padding(.horizontal, 4)

            DispatchTicket(topic: $topic, mode: $mode,
                           paper: paper, edge: paperEdge, ink: ink, coral: coral)
                .rotationEffect(.degrees(-0.7))

            HStack(spacing: 14) {
                DispatchThumbwheel(value: $turns, ink: ink, paper: paper)

                MiniLever(label: "FRESH CHATS", isOn: $freshChats, tint: blue, ink: ink)
                MiniLever(label: "TILE", isOn: .constant(true), tint: coral, ink: ink)

                Spacer()

                Button("INSPECT") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.62))

                DispatchButton(running: phase.isRunning, color: phase.isRunning ? coral : blue) {
                    phase = phase.isRunning ? .ready : .thinking
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .foregroundStyle(ink)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [shell.opacity(0.94), shell.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
                DispatchTexture()
                    .opacity(0.22)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
        .overlay(alignment: .leading) { CaseHandle().offset(x: -22) }
        .overlay(alignment: .trailing) { CaseHandle().offset(x: 22) }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DispatchLamp: View {
    let label: String
    let color: Color
    let lit: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(lit ? color : Color.black.opacity(0.15))
                .frame(width: 6, height: 6)
                .shadow(color: lit ? color.opacity(0.8) : .clear, radius: 3)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DispatchStation: View {
    let name: String
    let monogram: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 46, height: 46)
                Circle().stroke(color.opacity(0.55), lineWidth: 2).frame(width: 36, height: 36)
                Text(monogram)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(color)
            }
            Text(name)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1)
            Text(detail)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(width: 70)
    }
}

private struct DispatchRoute: View {
    let phase: LabPhase
    let ink: Color
    let blue: Color
    let coral: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let y = size.height / 2
                        var route = Path()
                        route.move(to: CGPoint(x: 2, y: y + 3))
                        route.addCurve(to: CGPoint(x: size.width - 2, y: y - 3),
                                       control1: CGPoint(x: size.width * 0.28, y: y - 18),
                                       control2: CGPoint(x: size.width * 0.72, y: y + 18))
                        context.stroke(route,
                                       with: .linearGradient(
                                        Gradient(colors: [blue, coral]),
                                        startPoint: .zero,
                                        endPoint: CGPoint(x: size.width, y: 0)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }

                    ZStack {
                        Circle().fill(Color.white).frame(width: 24, height: 24)
                        Image(systemName: "bird.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(phase == .complete ? coral : blue)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                    .offset(x: phase.fraction * max(geometry.size.width - 24, 0))
                }
            }
            .frame(height: 42)

            Text(phase.status.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(ink.opacity(0.62))
        }
    }
}

private struct DispatchTicket: View {
    @Binding var topic: String
    @Binding var mode: String
    let paper: Color
    let edge: Color
    let ink: Color
    let coral: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("SERVICE")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(edge)
                Menu(mode) {
                    Button("Brainstorm") { mode = "Brainstorm" }
                    Button("Debate") { mode = "Debate" }
                    Button("Critique") { mode = "Critique" }
                    Button("Custom") { mode = "Custom" }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(coral)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(coral, lineWidth: 1.5))
            }
            .frame(width: 92)

            Rectangle()
                .fill(edge.opacity(0.35))
                .frame(width: 1)
                .overlay {
                    VStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { _ in
                            Circle().fill(paper).frame(width: 3, height: 3)
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("CONSIGNMENT / OPENING MESSAGE")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(edge)
                TextField("What should they discuss?", text: $topic, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2...3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 67)
        .background(RoundedRectangle(cornerRadius: 6).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

private struct DispatchThumbwheel: View {
    @Binding var value: Int
    let ink: Color
    let paper: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("TURNS")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            HStack(spacing: 3) {
                Button { value = max(2, value - 2) } label: { Text("−") }
                Text(String(format: "%02d", value))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(paper)
                    .frame(width: 30, height: 20)
                    .background(RoundedRectangle(cornerRadius: 3).fill(ink))
                Button { value = min(40, value + 2) } label: { Text("+") }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .bold))
    }
}

private struct MiniLever: View {
    let label: String
    @Binding var isOn: Bool
    let tint: Color
    let ink: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 4) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(ink.opacity(0.18)).frame(width: 27, height: 12)
                    Circle().fill(isOn ? tint : Color.white.opacity(0.8))
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
                Text(label)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.68))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DispatchButton: View {
    let running: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                Image(systemName: running ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .help(running ? "Stop relay" : "Dispatch conversation")
    }
}

private struct DispatchTexture: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 8
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 8, y: y))
                line.addLine(to: CGPoint(x: size.width - 8, y: y))
                context.stroke(line, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
                y += 7
            }
        }
    }
}

// MARK: - B · Tape loop

/// A conversation as a two-reel tape loop: each side winds while composing,
/// the exposed tape becomes the handoff, and the transport controls run Errol.
private struct TapeLoopMock: View {
    @Binding var topic: String
    @Binding var phase: LabPhase
    @State private var mode = "CRITIQUE"

    private let shell = Color(red: 0.15, green: 0.13, blue: 0.20)
    private let shellEdge = Color(red: 0.29, green: 0.23, blue: 0.35)
    private let cream = Color(red: 0.94, green: 0.89, blue: 0.76)
    private let mint = Color(red: 0.31, green: 0.82, blue: 0.69)
    private let orange = Color(red: 0.98, green: 0.49, blue: 0.25)

    var body: some View {
        VStack(spacing: 13) {
            HStack {
                Text("ERROL / CONVERSATION LOOP")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(cream.opacity(0.7))
                Spacer()
                Text(phase.status.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(phase == .handoff ? orange : mint)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                TapePath(phase: phase, tape: cream.opacity(0.55), pulse: orange)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)

                HStack {
                    TapeReel(name: "CODEX", color: mint,
                             active: phase == .thinking || phase == .handoff)
                    Spacer()
                    VStack(spacing: 5) {
                        Text("TURN")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(cream.opacity(0.45))
                        Text(phase == .complete ? "12" : "07")
                            .font(.system(size: 19, weight: .black, design: .monospaced))
                            .foregroundStyle(orange)
                            .shadow(color: orange.opacity(0.45), radius: 4)
                    }
                    Spacer()
                    TapeReel(name: "CLAUDE", color: orange,
                             active: phase == .handoff || phase == .complete)
                }
                .padding(.horizontal, 27)
            }
            .frame(height: 126)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        ForEach(["BRAIN", "DEBATE", "CRITIQUE", "CUSTOM"], id: \.self) { item in
                            Button(item) { mode = item }
                                .buttonStyle(.plain)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(mode == item ? shell : cream.opacity(0.56))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(mode == item ? cream : .clear,
                                            in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Spacer()
                    Text("60 MIN · TYPE II")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(shell.opacity(0.46))
                }

                TextField("Conversation topic", text: $topic, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(shell)
                    .lineLimit(2...3)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 7).fill(cream))
            .overlay(alignment: .leading) {
                Rectangle().fill(orange).frame(width: 4).padding(.vertical, 6)
            }

            HStack(spacing: 9) {
                TapeToggle(label: "NEW", isOn: .constant(true), color: mint, cream: cream)
                TapeToggle(label: "TILE", isOn: .constant(true), color: orange, cream: cream)

                Spacer()

                Text("10 MAX")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(cream.opacity(0.5))

                TapeTransport(symbol: "scope", active: false, color: cream) {}
                TapeTransport(symbol: "stop.fill", active: phase.isRunning, color: orange) {
                    phase = .ready
                }
                TapeTransport(symbol: "play.fill", active: !phase.isRunning, color: mint) {
                    phase = .thinking
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [shellEdge, shell],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                TapeShellLines().clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .shadow(color: .black.opacity(0.38), radius: 16, y: 9)
        }
        .overlay(RoundedRectangle(cornerRadius: 26)
            .stroke(Color.white.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .topLeading) { HardwareScrew().padding(9) }
        .overlay(alignment: .topTrailing) { HardwareScrew().padding(9) }
        .overlay(alignment: .bottomLeading) { HardwareScrew().padding(9) }
        .overlay(alignment: .bottomTrailing) { HardwareScrew().padding(9) }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TapeReel: View {
    let name: String
    let color: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.black.opacity(0.5)).frame(width: 72, height: 72)
                Circle().stroke(color.opacity(active ? 0.8 : 0.28), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .shadow(color: active ? color.opacity(0.45) : .clear, radius: 5)
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(color.opacity(active ? 0.62 : 0.2))
                        .frame(width: 5, height: 19)
                        .offset(y: -17)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
                Circle().fill(color.opacity(active ? 0.9 : 0.35)).frame(width: 9, height: 9)
            }
            Text(name)
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(color)
        }
    }
}

private struct TapePath: View {
    let phase: LabPhase
    let tape: Color
    let pulse: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 20, y: size.height * 0.38))
            path.addCurve(to: CGPoint(x: size.width - 20, y: size.height * 0.38),
                          control1: CGPoint(x: size.width * 0.34, y: size.height * 0.92),
                          control2: CGPoint(x: size.width * 0.66, y: size.height * 0.92))
            context.stroke(path, with: .color(tape), lineWidth: 2)

            let x = 20 + phase.fraction * (size.width - 40)
            context.addFilter(.shadow(color: pulse.opacity(0.9), radius: 5))
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: size.height * 0.64,
                                                width: 8, height: 8)),
                         with: .color(pulse))
        }
    }
}

private struct TapeToggle: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color
    let cream: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOn ? color : cream.opacity(0.18))
                    .frame(width: 20, height: 8)
                    .shadow(color: isOn ? color.opacity(0.5) : .clear, radius: 2)
                Text(label)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(cream.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TapeTransport: View {
    let symbol: String
    let active: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(active ? Color.white : color)
                .frame(width: 30, height: 24)
                .background(active ? color : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(active ? 0.9 : 0.25)))
        }
        .buttonStyle(.plain)
    }
}

private struct TapeShellLines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 8
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.white.opacity(0.012)))
                y += 3
            }
        }
    }
}

// MARK: - C · Patch bay

/// A small operator's switchboard. Codex and Claude are sockets, Errol is
/// the live patch cable, and starting a run closes the circuit between them.
private struct PatchBayMock: View {
    @Binding var topic: String
    @Binding var phase: LabPhase
    @State private var mode = "DEBATE"
    @State private var turns = 10

    private let board = Color(red: 0.22, green: 0.31, blue: 0.30)
    private let boardDark = Color(red: 0.12, green: 0.19, blue: 0.19)
    private let brass = Color(red: 0.78, green: 0.60, blue: 0.28)
    private let paper = Color(red: 0.93, green: 0.88, blue: 0.73)
    private let coral = Color(red: 0.91, green: 0.35, blue: 0.24)
    private let mint = Color(red: 0.35, green: 0.78, blue: 0.62)

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 13) {
                HStack {
                    Text("ERROL / PATCH 01")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(paper)
                    Spacer()
                    Circle()
                        .fill(phase.isRunning ? mint : brass.opacity(0.35))
                        .frame(width: 8, height: 8)
                        .shadow(color: phase.isRunning ? mint.opacity(0.7) : .clear, radius: 4)
                    Text(phase.isRunning ? "LINE OPEN" : "STANDBY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(paper.opacity(0.62))
                }

                ZStack {
                    PatchCord(phase: phase, cable: coral, glow: mint)
                        .padding(.horizontal, 54)
                        .padding(.vertical, 14)
                    HStack {
                        PatchSocket(name: "CODEX", color: mint,
                                    active: phase == .thinking || phase == .handoff)
                        Spacer()
                        VStack(spacing: 5) {
                            Image(systemName: "bird.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(brass)
                            Text("OPERATOR")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(paper.opacity(0.45))
                        }
                        Spacer()
                        PatchSocket(name: "CLAUDE", color: coral,
                                    active: phase == .handoff || phase == .complete)
                    }
                    .padding(.horizontal, 34)
                }
                .frame(height: 118)
                .background(RoundedRectangle(cornerRadius: 14).fill(boardDark.opacity(0.62)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(brass.opacity(0.26)))

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mode)
                                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(coral)
                                .onTapGesture { mode = mode == "DEBATE" ? "CRITIQUE" : "DEBATE" }
                            Spacer()
                            Text("LINE 07")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(board.opacity(0.5))
                        }
                        TextField("Conversation topic", text: $topic, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(boardDark)
                            .lineLimit(2...3)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 4).fill(paper))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(brass.opacity(0.6)))

                    PatchCounter(value: $turns, brass: brass, paper: paper)
                }

                HStack {
                    Text(phase.status)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(paper.opacity(0.7))
                    Spacer()
                    Button("INSPECT") {}
                        .buttonStyle(.plain)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(paper.opacity(0.48))
                }
            }
            .padding(18)

            VStack(spacing: 12) {
                Text("CONNECT")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(boardDark.opacity(0.62))
                PatchKnifeSwitch(on: phase.isRunning, brass: brass, coral: coral) {
                    phase = phase.isRunning ? .ready : .thinking
                }
                Text(phase.isRunning ? "OPEN" : "CLOSED")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(boardDark.opacity(0.54))
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 14))
                    .foregroundStyle(boardDark.opacity(0.35))
            }
            .padding(.vertical, 18)
            .frame(width: 76)
            .background(brass.opacity(0.92))
        }
        .frame(width: 570)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [board, boardDark],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white.opacity(0.12)))
        .overlay(alignment: .topLeading) { HardwareScrew().padding(9) }
        .overlay(alignment: .bottomLeading) { HardwareScrew().padding(9) }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PatchSocket: View {
    let name: String
    let color: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.black.opacity(0.45)).frame(width: 56, height: 56)
                Circle().stroke(color.opacity(active ? 0.9 : 0.35), lineWidth: 3)
                    .frame(width: 43, height: 43)
                Circle().fill(color.opacity(active ? 0.9 : 0.28)).frame(width: 17, height: 17)
                Circle().fill(Color.black.opacity(0.75)).frame(width: 7, height: 7)
            }
            .shadow(color: active ? color.opacity(0.45) : .clear, radius: 5)
            Text(name)
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(color)
        }
    }
}

private struct PatchCord: View {
    let phase: LabPhase
    let cable: Color
    let glow: Color

    var body: some View {
        Canvas { context, size in
            var cord = Path()
            cord.move(to: CGPoint(x: 18, y: size.height * 0.34))
            cord.addCurve(to: CGPoint(x: size.width - 18, y: size.height * 0.34),
                          control1: CGPoint(x: size.width * 0.28, y: size.height * 1.06),
                          control2: CGPoint(x: size.width * 0.72, y: size.height * 1.06))
            context.stroke(cord, with: .color(Color.black.opacity(0.45)), lineWidth: 7)
            context.stroke(cord, with: .color(cable.opacity(0.9)), lineWidth: 4)

            let x = 18 + phase.fraction * (size.width - 36)
            context.addFilter(.shadow(color: glow.opacity(0.9), radius: 5))
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: size.height * 0.70,
                                                width: 8, height: 8)),
                         with: .color(glow))
        }
    }
}

private struct PatchCounter: View {
    @Binding var value: Int
    let brass: Color
    let paper: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("MAX")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(paper.opacity(0.55))
            Button { value = value >= 20 ? 2 : value + 2 } label: {
                Text(String(format: "%02d", value))
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(brass)
                    .frame(width: 38, height: 32)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(brass.opacity(0.4)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PatchKnifeSwitch: View {
    let on: Bool
    let brass: Color
    let coral: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill(Color.black.opacity(0.18)).frame(width: 34, height: 74)
                Circle().fill(Color.black.opacity(0.5)).frame(width: 22, height: 22).offset(y: 24)
                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.8), brass],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 8, height: 49)
                    .rotationEffect(.degrees(on ? 0 : -28), anchor: .bottom)
                    .offset(x: on ? 0 : -10, y: -5)
                Circle()
                    .fill(on ? coral : brass)
                    .frame(width: 18, height: 18)
                    .offset(x: on ? 0 : -19, y: on ? -27 : -19)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .help(on ? "Stop relay" : "Connect relay")
    }
}

// MARK: - Hardware details

private struct HardwareScrew: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.22)).frame(width: 10, height: 10)
            Capsule().fill(Color.white.opacity(0.34)).frame(width: 6, height: 1)
                .rotationEffect(.degrees(-24))
        }
    }
}

private struct CaseHandle: View {
    var body: some View {
        Capsule()
            .stroke(Color.black.opacity(0.28), lineWidth: 5)
            .frame(width: 38, height: 78)
    }
}

private enum LabColor {
    static let stage = Color(red: 0.91, green: 0.90, blue: 0.875)
}

#if !DESIGN_LAB_SNAPSHOT

private struct ConceptPreviewHarness<Content: View>: View {
    @State private var topic = "Find the strongest counterargument to our launch plan"
    @State private var phase: LabPhase = .handoff
    @ViewBuilder let content: (Binding<String>, Binding<LabPhase>) -> Content

    var body: some View {
        VStack(spacing: 18) {
            content($topic, $phase)
            Picker("Phase", selection: $phase) {
                ForEach(LabPhase.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 420)
        }
        .padding(38)
        .background(LabColor.stage)
    }
}

#Preview("Control panel concepts") {
    ControlPanelDesignLab()
}

#Preview("A · Dispatch desk") {
    ConceptPreviewHarness { DispatchDeskMock(topic: $0, phase: $1) }
}

#Preview("B · Tape loop") {
    ConceptPreviewHarness { TapeLoopMock(topic: $0, phase: $1) }
}

#Preview("C · Patch bay") {
    ConceptPreviewHarness { PatchBayMock(topic: $0, phase: $1) }
}

#endif
#endif

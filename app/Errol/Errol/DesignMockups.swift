// Visual design studies for the Errol UI, NOT wired into the app — nothing
// here references RelayController or the live relay. Four options render the
// same surface (the compact head unit a run is driven from) from one shared
// MockRun state, so the directions stay comparable phase by phase:
//
//   A. WireframeInstrumentMock — the neutral-gray state study from
//      docs/ui-brainstorm-conversation-appliance.md §7: every phase must be
//      legible with lamps, needles, and counters alone.
//   B. StudioChassisMock — the appliance's default chassis: warm metal,
//      candy accents, mode dial, luggage-tag topic.
//   C. NightSignalMock — the appliance's retro hero: smoked acrylic,
//      phosphor green and amber, red reserved for true failures.
//   D. QuietFrameCardMock — the control card from
//      docs/ui-brainstorm-living-canvas.md: calm shell, a small current
//      field, and the Duet Score rail.
//
// Preview any option in Xcode (each has a #Preview with a phase picker), or
// delete this file without consequence once real UI work begins.

#if DEBUG

import SwiftUI

// MARK: - Shared mock state

/// One canonical run, frozen at a chosen phase. ChatGPT sits on the left and
/// Claude on the right, matching the tiling arrangement. The scenario is
/// fixed: ChatGPT composes, Errol delivers rightward, Claude challenges,
/// signs off first, and the run completes on the mutual sign-off.
enum MockPhase: String, CaseIterable, Identifiable {
    case idle = "Idle"
    case thinking = "Thinking"
    case handoff = "Handoff"
    case waiting = "Waiting"
    case disagreement = "Challenge"
    case firstSignoff = "First sign-off"
    case complete = "Complete"

    var id: String { rawValue }
}

struct MockRun {
    var phase: MockPhase = .thinking

    static let shape = "Debate"
    static let topic = "Are code comments for the why or the what?"

    var turn: Int { phase == .complete ? 12 : 7 }
    var leftComposing: Bool { phase == .thinking }
    var delivering: Bool { phase == .handoff }
    var rightArmed: Bool { phase == .waiting }
    var challenged: Bool { phase == .disagreement }
    var rightSealed: Bool { phase == .firstSignoff || phase == .complete }
    var leftSealed: Bool { phase == .complete }
    var running: Bool { phase != .idle && phase != .complete }

    /// The challenge stays on the record once it has happened, even after
    /// it resolves; `challenged` alone means it is currently open.
    var challengeOnRecord: Bool {
        phase == .disagreement || phase == .firstSignoff || phase == .complete
    }

    /// Where the courier sits along the route, 0 (left) to 1 (right).
    var courierFraction: CGFloat {
        switch phase {
        case .idle, .thinking: 0.04
        case .handoff, .disagreement: 0.5
        case .waiting, .firstSignoff: 0.96
        case .complete: 0.5
        }
    }

    var statusLine: String {
        switch phase {
        case .idle: "Ready"
        case .thinking: "ChatGPT is composing"
        case .handoff: "Delivering to Claude"
        case .waiting: "Waiting on Claude"
        case .disagreement: "Challenge open"
        case .firstSignoff: "Claude signed off"
        case .complete: "Run complete"
        }
    }
}

// MARK: - Shared instrument parts

/// A half-circle gauge with a needle; the appliance options share it and
/// retint it per chassis.
private struct NeedleGauge: View {
    var level: Double
    var size: CGFloat = 54
    var track: Color
    var needle: Color
    var glow = false

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height - 3)
            let r = min(sz.width / 2 - 4, sz.height - 8)
            var arc = Path()
            arc.addArc(center: c, radius: r,
                       startAngle: .degrees(180), endAngle: .degrees(360),
                       clockwise: false)
            ctx.stroke(arc, with: .color(track),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for i in 0...4 {
                let a = Angle.degrees(180 + Double(i) * 45).radians
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * (r - 6), y: c.y + sin(a) * (r - 6)))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * (r - 2), y: c.y + sin(a) * (r - 2)))
                ctx.stroke(tick, with: .color(track.opacity(0.7)), lineWidth: 1)
            }
            if glow {
                ctx.addFilter(.shadow(color: needle.opacity(0.8), radius: 3))
            }
            let a = Angle.degrees(180 + 180 * min(max(level, 0), 1)).radians
            var hand = Path()
            hand.move(to: c)
            hand.addLine(to: CGPoint(x: c.x + cos(a) * (r - 8), y: c.y + sin(a) * (r - 8)))
            ctx.stroke(hand, with: .color(needle),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                     with: .color(needle))
        }
        .frame(width: size, height: size * 0.6)
    }
}

/// A labeled indicator lamp; off is a visible state, not an absence.
private struct Lamp: View {
    var label: String
    var on: Bool
    var onColor: Color
    var offColor: Color
    var textColor: Color
    /// A dark lamp color makes the glow read as a smudge, so the wireframe
    /// option turns it off.
    var glow = true

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(on ? onColor : offColor)
                .overlay(Circle().stroke(textColor.opacity(0.35), lineWidth: 1))
                .frame(width: 9, height: 9)
                .shadow(color: on && glow ? onColor.opacity(0.7) : .clear, radius: 3)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(textColor)
        }
    }
}

/// Boxed rolling digits, the appliance's turn counter.
private struct Odometer: View {
    var value: Int
    var digits = 2
    var cell: Color
    var text: Color

    var body: some View {
        HStack(spacing: 2) {
            let padded = String(format: "%0\(digits)d", value)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(text)
                    .frame(width: 16, height: 21)
                    .background(RoundedRectangle(cornerRadius: 3).fill(cell))
            }
        }
    }
}

/// The per-side sign-off indicator: an armed ring that fills when that side
/// signs off.
private struct SealMark: View {
    var sealed: Bool
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(sealed ? 1 : 0.35), lineWidth: 1.5)
                .frame(width: 13, height: 13)
            if sealed {
                Circle().fill(color).frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Option A · Wireframe instrument (neutral gray)

/// The appliance doc's first build-order test: prove every semantic state
/// with monochrome lamps, needles, counters, and labels before any chassis
/// styling or motion exists.
struct WireframeInstrumentMock: View {
    var run: MockRun

    private let ink = Color(white: 0.20)
    private let faint = Color(white: 0.52)
    private let paper = Color(white: 0.94)
    private let well = Color(white: 0.885)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ERROL · INSTRUMENT STUDY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(faint)
                Spacer()
                Text(run.running ? "IN RUN" : (run.phase == .complete ? "DONE" : "READY"))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(ink)
            }

            HStack(alignment: .top, spacing: 14) {
                participant(name: "CHATGPT",
                            thinking: run.leftComposing,
                            armed: false,
                            sealed: run.leftSealed)
                centerDeck
                participant(name: "CLAUDE",
                            thinking: false,
                            armed: run.rightArmed,
                            sealed: run.rightSealed)
            }

            HStack(spacing: 8) {
                Text("[ \(MockRun.shape.uppercased()) ]")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ink)
                Text(MockRun.topic)
                    .font(.system(size: 10))
                    .foregroundColor(faint)
                    .lineLimit(1)
                Spacer()
                wireButton("RUN", disabled: run.running)
                wireButton("STOP", disabled: !run.running)
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(RoundedRectangle(cornerRadius: 10).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ink.opacity(0.3)))
    }

    private func participant(name: String, thinking: Bool, armed: Bool, sealed: Bool) -> some View {
        VStack(spacing: 8) {
            NeedleGauge(level: thinking ? 0.72 : 0.08, track: faint, needle: ink)
            Text(name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(ink)
            HStack(spacing: 10) {
                Lamp(label: "THINK", on: thinking, onColor: ink, offColor: paper,
                     textColor: faint, glow: false)
                Lamp(label: "ARMED", on: armed, onColor: ink, offColor: paper,
                     textColor: faint, glow: false)
                VStack(spacing: 3) {
                    SealMark(sealed: sealed, color: ink)
                    Text("SEAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(faint)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(well))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(faint.opacity(0.5)))
    }

    private var centerDeck: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("TURN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(faint)
                Odometer(value: run.turn, cell: ink, text: paper)
            }
            route
            Text(run.statusLine.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(ink)
                .lineLimit(1)
                .fixedSize()
            Text("CHALLENGE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(ink, lineWidth: 1))
                .opacity(run.challenged ? 1 : 0)
        }
        .frame(width: 150)
    }

    /// The route in wireframe: a plain line, a direction chevron, and the
    /// courier as an open circle. A challenge kinks the line rather than
    /// coloring it.
    private var route: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var line = Path()
            if run.challenged {
                line.move(to: CGPoint(x: 2, y: midY))
                line.addLine(to: CGPoint(x: size.width * 0.42, y: midY))
                line.addLine(to: CGPoint(x: size.width * 0.5, y: midY - 5))
                line.addLine(to: CGPoint(x: size.width * 0.58, y: midY + 5))
                line.addLine(to: CGPoint(x: size.width * 0.66, y: midY))
                line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            } else {
                line.move(to: CGPoint(x: 2, y: midY))
                line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            }
            ctx.stroke(line, with: .color(faint),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round,
                                          dash: run.running ? [] : [3, 3]))
            if run.running {
                var chevron = Path()
                let cx = size.width - 12
                chevron.move(to: CGPoint(x: cx - 4, y: midY - 4))
                chevron.addLine(to: CGPoint(x: cx, y: midY))
                chevron.addLine(to: CGPoint(x: cx - 4, y: midY + 4))
                ctx.stroke(chevron, with: .color(ink), lineWidth: 1.5)
            }
            let cx = 6 + run.courierFraction * (size.width - 12)
            let dot = CGRect(x: cx - 5, y: midY - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: dot), with: .color(paper))
            ctx.stroke(Path(ellipseIn: dot), with: .color(ink), lineWidth: 1.5)
        }
        .frame(height: 22)
    }

    private func wireButton(_ label: String, disabled: Bool) -> some View {
        Button {} label: {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(disabled ? faint : ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(disabled ? faint : ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option B · Studio chassis

/// The appliance's default chassis: warm light-gray metal, restrained
/// industrial proportions, dot-matrix labels used sparingly, and a few
/// candy-colored controls. ChatGPT keeps a soft green, Claude a warm coral.
struct StudioChassisMock: View {
    var run: MockRun

    private let ink = Color(red: 0.22, green: 0.21, blue: 0.20)
    private let faint = Color(red: 0.48, green: 0.47, blue: 0.45)
    private let shellTop = Color(red: 0.935, green: 0.925, blue: 0.905)
    private let shellBottom = Color(red: 0.855, green: 0.845, blue: 0.825)
    private let chatgptGreen = Color(red: 0.35, green: 0.62, blue: 0.53)
    private let claudeCoral = Color(red: 0.83, green: 0.47, blue: 0.35)
    private let grape = Color(red: 0.52, green: 0.36, blue: 0.72)
    private let amber = Color(red: 0.92, green: 0.68, blue: 0.25)
    private let manila = Color(red: 0.95, green: 0.89, blue: 0.76)
    private let tagBrown = Color(red: 0.55, green: 0.44, blue: 0.30)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 9))
                        .foregroundColor(ink)
                    Text("ERROL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(ink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.55)))
                Spacer()
                HStack(spacing: 12) {
                    Lamp(label: "PWR", on: true, onColor: chatgptGreen,
                         offColor: shellBottom, textColor: faint)
                    Lamp(label: "SEND", on: run.delivering, onColor: amber,
                         offColor: shellBottom, textColor: faint)
                    Lamp(label: "CHLG", on: run.challenged, onColor: amber,
                         offColor: shellBottom, textColor: faint)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                participantModule(name: "CHATGPT", color: chatgptGreen,
                                  thinking: run.leftComposing, sealed: run.leftSealed)
                centerDeck
                participantModule(name: "CLAUDE", color: claudeCoral,
                                  thinking: run.rightArmed, sealed: run.rightSealed)
            }

            HStack(alignment: .center, spacing: 14) {
                modeDial
                topicTag
                Spacer(minLength: 0)
                startButton
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [shellTop, shellBottom],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
    }

    /// The participant glyph is concentric rings that light from the core
    /// outward while that side is active; the seal sits below as a wax dot.
    private func participantModule(name: String, color: Color, thinking: Bool, sealed: Bool) -> some View {
        VStack(spacing: 7) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(color.opacity(thinking ? 0.85 - Double(ring) * 0.25 : 0.18),
                                lineWidth: 2)
                        .frame(width: CGFloat(18 + ring * 12),
                               height: CGFloat(18 + ring * 12))
                }
                Circle()
                    .fill(color.opacity(thinking ? 1 : 0.4))
                    .frame(width: 8, height: 8)
            }
            .frame(height: 46)
            Text(name)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(ink)
            SealMark(sealed: sealed, color: color)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4)))
    }

    private var centerDeck: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("TURN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(faint)
                Odometer(value: run.turn, cell: ink, text: manila)
            }
            routeTrack
            Text(run.statusLine.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(faint)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 150)
    }

    /// An inset track the courier rides; the amber challenge state pulls the
    /// track into a visible dashed tension rather than turning anything red.
    private var routeTrack: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(red: 0.78, green: 0.77, blue: 0.75))
                .frame(height: 8)
            if run.challenged {
                Capsule()
                    .stroke(amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: 8)
            }
            Circle()
                .fill(.white)
                .frame(width: 17, height: 17)
                .overlay(Image(systemName: "bird.fill")
                    .font(.system(size: 8))
                    .foregroundColor(ink))
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .offset(x: run.courierFraction * (150 - 17))
        }
        .frame(width: 150, height: 18)
    }

    /// The conversation shape lives on a chunky mode dial, not in a picker.
    private var modeDial: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.white, shellBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(faint)
                        .frame(width: 1.5, height: 5)
                        .offset(y: -26)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
                Capsule()
                    .fill(grape)
                    .frame(width: 4, height: 15)
                    .offset(y: -10)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: 60, height: 60)
            Text(MockRun.shape.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(ink)
        }
    }

    /// The topic rides a removable luggage tag: configuration as loading the
    /// machine, not filling a form.
    private var topicTag: some View {
        HStack(spacing: 0) {
            Circle()
                .stroke(tagBrown, lineWidth: 1.5)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(tagBrown)
                .frame(width: 12, height: 1.5)
            Text(MockRun.topic)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(tagBrown)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 4).fill(manila))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(tagBrown.opacity(0.6)))
                .rotationEffect(.degrees(-1.2))
        }
    }

    private var startButton: some View {
        Button {} label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: run.running
                            ? [claudeCoral, claudeCoral.opacity(0.75)]
                            : [chatgptGreen, chatgptGreen.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                if run.running {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option C · Night Signal chassis

/// The retro hero: near-black translucent acrylic with hints of internal
/// traces, phosphor green for signal, warm amber for labels and warnings,
/// and red held in reserve for true failures (never shown here).
struct NightSignalMock: View {
    var run: MockRun

    private let shell = Color(red: 0.055, green: 0.07, blue: 0.085)
    private let shellEdge = Color(red: 0.13, green: 0.16, blue: 0.18)
    private let phosphor = Color(red: 0.30, green: 0.95, blue: 0.55)
    private let amber = Color(red: 1.0, green: 0.72, blue: 0.33)
    private let dim = Color.white.opacity(0.28)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ERROL // NIGHT SIGNAL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(phosphor.opacity(0.7))
                Spacer()
                HStack(spacing: 4) {
                    Text("TURN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(dim)
                    Text(String(format: "%02d", run.turn))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(amber)
                        .shadow(color: amber.opacity(0.9), radius: 4)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                sideColumn(name: "CHATGPT", active: run.leftComposing, sealed: run.leftSealed)
                VStack(spacing: 6) {
                    NeedleGauge(level: gaugeLevel, size: 66,
                                track: dim, needle: phosphor, glow: true)
                    Text("SIGNAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(dim)
                    routeTrace
                    Text(run.challenged ? "◆ CHALLENGE" : " ")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(amber)
                        .shadow(color: run.challenged ? amber.opacity(0.8) : .clear, radius: 3)
                }
                .frame(width: 160)
                sideColumn(name: "CLAUDE", active: run.rightArmed, sealed: run.rightSealed)
            }

            HStack {
                Text("▸ " + run.statusLine.uppercased() + "_")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(phosphor)
                    .shadow(color: phosphor.opacity(0.7), radius: 3)
                Spacer()
                nightButton("RUN", lit: !run.running)
                nightButton("STOP", lit: run.running)
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [shellEdge, shell],
                                         startPoint: .top, endPoint: .bottom))
                innerTraces
                scanlines
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
        )
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var gaugeLevel: Double {
        switch run.phase {
        case .idle: 0.06
        case .thinking: 0.68
        case .handoff: 0.9
        case .waiting: 0.35
        case .disagreement: 0.8
        case .firstSignoff: 0.5
        case .complete: 0.06
        }
    }

    private func sideColumn(name: String, active: Bool, sealed: Bool) -> some View {
        VStack(spacing: 7) {
            Text(name)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(amber.opacity(0.9))
            VStack(spacing: 3) {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < (active ? 4 : 1) ? phosphor : Color.white.opacity(0.07))
                        .frame(width: 20, height: 4)
                        .shadow(color: i < (active ? 4 : 1) ? phosphor.opacity(0.8) : .clear,
                                radius: 2)
                }
            }
            SealMark(sealed: sealed, color: phosphor)
                .shadow(color: sealed ? phosphor.opacity(0.8) : .clear, radius: 3)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
    }

    /// The route as an internal light trace with a traveling pulse.
    private var routeTrace: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 2, y: midY))
            line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            ctx.stroke(line, with: .color(phosphor.opacity(run.running ? 0.5 : 0.15)),
                       lineWidth: 1.5)
            let cx = 6 + run.courierFraction * (size.width - 12)
            ctx.addFilter(.shadow(color: phosphor.opacity(0.9), radius: 4))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: midY - 3.5, width: 7, height: 7)),
                     with: .color(phosphor))
        }
        .frame(width: 150, height: 14)
    }

    /// Hints of components beneath the smoked acrylic.
    private var innerTraces: some View {
        Canvas { ctx, size in
            let lines: [[CGPoint]] = [
                [CGPoint(x: 0.06, y: 0.9), CGPoint(x: 0.06, y: 0.42),
                 CGPoint(x: 0.2, y: 0.42), CGPoint(x: 0.2, y: 0.14)],
                [CGPoint(x: 0.94, y: 0.1), CGPoint(x: 0.94, y: 0.6),
                 CGPoint(x: 0.8, y: 0.6), CGPoint(x: 0.8, y: 0.92)],
                [CGPoint(x: 0.35, y: 0.97), CGPoint(x: 0.35, y: 0.8),
                 CGPoint(x: 0.62, y: 0.8), CGPoint(x: 0.62, y: 0.95)],
            ]
            for pts in lines {
                var p = Path()
                p.move(to: CGPoint(x: pts[0].x * size.width, y: pts[0].y * size.height))
                for pt in pts.dropFirst() {
                    p.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                }
                ctx.stroke(p, with: .color(phosphor.opacity(0.09)), lineWidth: 1)
                for pt in [pts.first!, pts.last!] {
                    let c = CGPoint(x: pt.x * size.width, y: pt.y * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                             with: .color(phosphor.opacity(0.12)))
                }
            }
        }
    }

    private var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.white.opacity(0.02)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }

    private func nightButton(_ label: String, lit: Bool) -> some View {
        Button {} label: {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(lit ? amber : dim)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(lit ? amber.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: lit ? amber.opacity(0.5) : .clear, radius: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option D · Quiet frame control card

/// The living-canvas direction: a restrained contemporary card whose only
/// expressive element is a small current field (a window onto the world the
/// theater would show full-display) above the observational Duet Score rail.
struct QuietFrameCardMock: View {
    var run: MockRun

    private let ink = Color(red: 0.17, green: 0.16, blue: 0.15)
    private let gray = Color(red: 0.52, green: 0.50, blue: 0.47)
    private let card = Color(red: 0.97, green: 0.96, blue: 0.94)
    private let fieldBed = Color(red: 0.935, green: 0.925, blue: 0.90)
    private let chatgptTeal = Color(red: 0.29, green: 0.58, blue: 0.55)
    private let claudeCoral = Color(red: 0.80, green: 0.49, blue: 0.38)
    private let amber = Color(red: 0.85, green: 0.62, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MockRun.shape.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.8)
                    .foregroundColor(gray)
                Text(MockRun.topic)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                chip(name: "ChatGPT", color: chatgptTeal, active: run.leftComposing)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(gray)
                chip(name: "Claude", color: claudeCoral,
                     active: run.rightArmed || run.delivering)
                Spacer()
            }

            CurrentFieldMock(run: run, bed: fieldBed,
                             left: chatgptTeal, right: claudeCoral)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            DuetScoreRail(run: run, left: chatgptTeal, right: claudeCoral,
                          accent: amber, baseline: ink)

            Text(caption)
                .font(.system(size: 11))
                .foregroundColor(gray)

            HStack(spacing: 8) {
                Button {} label: {
                    Text(primaryLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(card)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(ink))
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ink)
                        .padding(7)
                        .overlay(Circle().stroke(gray.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help("Enter theater")
                Spacer()
                Button {} label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundColor(gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 16).fill(card)
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.black.opacity(0.08)))
    }

    private func chip(name: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(active ? 0.20 : 0.08)))
        .overlay(Capsule().stroke(color.opacity(active ? 0.55 : 0.2)))
    }

    private var caption: String {
        switch run.phase {
        case .idle: "Ready · the theater opens when the run begins"
        case .thinking: "ChatGPT is composing · turn 7"
        case .handoff: "Delivering to Claude · turn 7"
        case .waiting: "Waiting on Claude · turn 7"
        case .disagreement: "Challenge open · Claude pressed on the second claim"
        case .firstSignoff: "Claude signed off · waiting on ChatGPT"
        case .complete: "Run complete · 12 turns, one challenge resolved"
        }
    }

    private var primaryLabel: String {
        switch run.phase {
        case .idle: "Begin run"
        case .complete: "Open transcript"
        default: "Pause"
        }
    }
}

/// A still (reduced-motion) rendering of the currents layer: two soft color
/// fields whose flow lines cross between the sides. A challenge roughens the
/// water and opens a fracture; completion settles into a seal.
private struct CurrentFieldMock: View {
    var run: MockRun
    var bed: Color
    var left: Color
    var right: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bed))

            let leftGlow = run.leftComposing ? 0.34 : 0.15
            let rightGlow = (run.rightArmed || run.rightSealed) ? 0.34 : 0.15
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.3, y: -h * 0.3,
                                            width: w * 0.85, height: h * 1.6)),
                     with: .radialGradient(
                        Gradient(colors: [left.opacity(leftGlow), .clear]),
                        center: CGPoint(x: w * 0.1, y: h * 0.5),
                        startRadius: 0, endRadius: w * 0.5))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.45, y: -h * 0.3,
                                            width: w * 0.85, height: h * 1.6)),
                     with: .radialGradient(
                        Gradient(colors: [right.opacity(rightGlow), .clear]),
                        center: CGPoint(x: w * 0.9, y: h * 0.5),
                        startRadius: 0, endRadius: w * 0.5))

            let amp: Double = run.challenged ? 8 : (run.phase == .complete ? 1.5 : 3.5)
            let leftLine = run.leftComposing ? 0.55 : 0.28
            let rightLine = (run.rightArmed || run.delivering) ? 0.55 : 0.28
            for i in 0..<7 {
                let yBase = h * (0.14 + 0.12 * Double(i))
                var p = Path()
                var x: Double = 6
                var first = true
                while x <= w - 6 {
                    let rough = run.challenged ? 0.5 + 0.9 * sin(x / w * .pi) : 1
                    let y = yBase + sin(x / 24 + Double(i) * 1.7) * amp * rough
                    if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 6
                }
                ctx.stroke(p, with: .linearGradient(
                    Gradient(colors: [left.opacity(leftLine), right.opacity(rightLine)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: w, y: 0)), lineWidth: 1.2)
            }

            if run.challenged {
                var f = Path()
                var y = h * 0.1
                var fx = w * 0.52
                f.move(to: CGPoint(x: fx, y: y))
                var i = 0
                while y < h * 0.9 {
                    y += h * 0.16
                    fx += i.isMultiple(of: 2) ? 8 : -11
                    f.addLine(to: CGPoint(x: fx, y: y))
                    i += 1
                }
                ctx.stroke(f, with: .color(right.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            if run.delivering {
                let c = CGPoint(x: w * 0.5, y: h * 0.5)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                           with: .color(.white.opacity(0.7)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                         with: .color(.white))
            }

            if run.phase == .complete {
                let c = CGPoint(x: w * 0.5, y: h * 0.5)
                for (r, o) in [(16.0, 0.55), (10.0, 0.8)] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(left.opacity(o)), lineWidth: 1.2)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                         with: .color(right))
            }
        }
    }
}

/// The thin two-lane status rail: activity bars per participant, delivery
/// ticks between the lanes, the challenge diamond on the record, sign-off
/// marks at the end, and a cursor at "now" while running. Observable events
/// only — no synthesized agreement measure.
private struct DuetScoreRail: View {
    var run: MockRun
    var left: Color
    var right: Color
    var accent: Color
    var baseline: Color

    var body: some View {
        Canvas { ctx, size in
            let topY = size.height * 0.3
            let botY = size.height * 0.7
            func x(_ f: Double) -> CGFloat { f * size.width }

            for y in [topY, botY] {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(baseline.opacity(0.1)), lineWidth: 1)
            }

            let leftSegs: [(Double, Double)] = [(0.02, 0.09), (0.24, 0.10), (0.47, 0.08), (0.70, 0.10)]
            let rightSegs: [(Double, Double)] = [(0.12, 0.10), (0.36, 0.09), (0.57, 0.11), (0.82, 0.07)]
            for (start, len) in leftSegs {
                ctx.fill(Path(roundedRect: CGRect(x: x(start), y: topY - 2.5,
                                                  width: x(len), height: 5),
                              cornerRadius: 2.5),
                         with: .color(left.opacity(0.85)))
            }
            for (start, len) in rightSegs {
                ctx.fill(Path(roundedRect: CGRect(x: x(start), y: botY - 2.5,
                                                  width: x(len), height: 5),
                              cornerRadius: 2.5),
                         with: .color(right.opacity(0.85)))
            }

            for d in [0.115, 0.225, 0.345, 0.455, 0.565, 0.685, 0.81] {
                var p = Path()
                p.move(to: CGPoint(x: x(d), y: topY + 4))
                p.addLine(to: CGPoint(x: x(d), y: botY - 4))
                ctx.stroke(p, with: .color(baseline.opacity(0.28)), lineWidth: 1)
            }

            if run.challengeOnRecord {
                let c = CGPoint(x: x(0.575), y: size.height / 2)
                let r: CGFloat = run.challenged ? 5 : 3.5
                var d = Path()
                d.move(to: CGPoint(x: c.x, y: c.y - r))
                d.addLine(to: CGPoint(x: c.x + r, y: c.y))
                d.addLine(to: CGPoint(x: c.x, y: c.y + r))
                d.addLine(to: CGPoint(x: c.x - r, y: c.y))
                d.closeSubpath()
                ctx.fill(d, with: .color(accent))
            }

            if run.leftSealed {
                ctx.fill(Path(ellipseIn: CGRect(x: x(0.965) - 3, y: topY - 3, width: 6, height: 6)),
                         with: .color(left))
            }
            if run.rightSealed {
                ctx.fill(Path(ellipseIn: CGRect(x: x(0.965) - 3, y: botY - 3, width: 6, height: 6)),
                         with: .color(right))
            }

            if run.running {
                var p = Path()
                p.move(to: CGPoint(x: x(0.90), y: 1))
                p.addLine(to: CGPoint(x: x(0.90), y: size.height - 1))
                ctx.stroke(p, with: .color(baseline.opacity(0.45)), lineWidth: 1)
            }
        }
        .frame(height: 26)
    }
}

// MARK: - Previews

/// Hosts one option above a phase picker so the Xcode canvas can step the
/// same mock through every semantic state.
private struct MockPhaseHarness<Content: View>: View {
    @State private var phase: MockPhase = .thinking
    @ViewBuilder var content: (MockRun) -> Content

    var body: some View {
        VStack(spacing: 16) {
            content(MockRun(phase: phase))
            Picker("Phase", selection: $phase) {
                ForEach(MockPhase.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 470)
        }
        .padding(24)
        .background(Color(red: 0.96, green: 0.955, blue: 0.945))
    }
}

#Preview("A · Wireframe instrument") {
    MockPhaseHarness { WireframeInstrumentMock(run: $0) }
}

#Preview("B · Studio chassis") {
    MockPhaseHarness { StudioChassisMock(run: $0) }
}

#Preview("C · Night Signal") {
    MockPhaseHarness { NightSignalMock(run: $0) }
}

#Preview("D · Quiet frame card") {
    MockPhaseHarness { QuietFrameCardMock(run: $0) }
}

#Preview("All options · thinking") {
    ScrollView {
        VStack(spacing: 24) {
            WireframeInstrumentMock(run: MockRun(phase: .thinking))
            StudioChassisMock(run: MockRun(phase: .thinking))
            NightSignalMock(run: MockRun(phase: .thinking))
            QuietFrameCardMock(run: MockRun(phase: .thinking))
        }
        .padding(24)
    }
    .background(Color(red: 0.96, green: 0.955, blue: 0.945))
}

#endif

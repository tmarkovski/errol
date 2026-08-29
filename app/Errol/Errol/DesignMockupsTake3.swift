// Third round of visual design studies, NOT wired into the app. Take one's
// two most committed directions — the wireframe instrument (every state
// legible from lamps and labels alone) and Night Signal (a chassis with a
// real point of view) — reinterpreted through Apple's Liquid Glass
// material language: floating translucent surfaces over a colorful
// desktop, identity carried by tinted glass instead of painted plastic,
// and the system material doing the atmospheric work the smoked acrylic
// used to do. The instrument vocabulary survives (readiness lamps, seal
// marks, the route bead, level bars); the chassis is gone.
//
// Two surfaces, the same pairing take two used:
//
//   1. GlassConsoleMock — the full head unit before a run: the topic is
//      loaded and the shape chosen, and the console is waiting for both
//      agents' readiness checks to clear before Begin lights up. This
//      moment precedes MockPhase.idle, so it runs on its own small
//      GlassPrepPhase state rather than the shared MockRun.
//   2. GlassCompanionMock — the shrunk in-run pane: nothing but the two
//      agents' live status tiles and a prominent pause/resume button
//      between them, driven by the shared MockRun plus a paused flag.
//
// These use the real .glassEffect / GlassEffectContainer APIs (macOS 26),
// so the Xcode canvas renders true refraction over the preview wallpaper.
// Delete this file without consequence once real UI work begins.

#if DEBUG

import SwiftUI

// MARK: - Palette

/// Agent identity colors carried over from take one so the studies stay
/// comparable; everything else defers to the system material.
private enum GlassInk {
    static let teal = Color(red: 0.29, green: 0.58, blue: 0.55)   // ChatGPT
    static let coral = Color(red: 0.80, green: 0.49, blue: 0.38)  // Claude
    static let amber = Color(red: 0.92, green: 0.68, blue: 0.30)  // challenge
}

/// A stand-in desktop for the previews. Liquid Glass only reads as glass
/// with color behind it, so the harnesses float the surfaces over a soft
/// wallpaper instead of the flat studio gray the earlier takes used.
private struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.83, blue: 0.92),
                    Color(red: 0.86, green: 0.79, blue: 0.89),
                    Color(red: 0.76, green: 0.88, blue: 0.86),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(GlassInk.teal.opacity(0.42))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -180, y: -130)
            Circle()
                .fill(GlassInk.coral.opacity(0.38))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 200, y: 40)
            Circle()
                .fill(Color(red: 0.48, green: 0.42, blue: 0.80).opacity(0.32))
                .frame(width: 300, height: 300)
                .blur(radius: 75)
                .offset(x: 30, y: 190)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Prep state

/// The pre-run staging sequence the full console renders: Errol finds the
/// two agent windows, brings them forward, and arms their reply boxes.
/// Begin stays quiet until every check on both sides has cleared.
enum GlassPrepPhase: String, CaseIterable, Identifiable {
    case connecting = "Connecting"
    case arming = "Arming"
    case ready = "Ready"

    var id: String { rawValue }

    var statusText: String {
        switch self {
        case .connecting: "Finding windows"
        case .arming: "Arming reply boxes"
        case .ready: "Ready to begin"
        }
    }
}

// MARK: - Shared glass parts

/// One readiness line inside an agent card. Off is still a visible state —
/// the wireframe rule — so pending renders as a dotted ring, not a blank.
private struct GlassCheckRow: View {
    enum Status { case pending, working, done }

    var label: String
    var status: Status
    var tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Group {
                switch status {
                case .pending:
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                case .working:
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 9, height: 9)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 12)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(status == .pending ? .tertiary : .secondary)
            Spacer(minLength: 0)
        }
    }
}

/// The activity meter the companion tiles use: Night Signal's little bar
/// stack laid on its side and re-cut in tinted glass tones.
private struct GlassPulseBars: View {
    var level: Int   // 0...4 lit
    var tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < level ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 14, height: 4)
            }
        }
    }
}

// MARK: - Surface 1 · Glass console (full, getting ready)

/// The full head unit at the moment before a run: two agent cards working
/// through their readiness checks, the route dashed until it is live, and
/// a Begin button that only becomes prominent when everything has cleared.
struct GlassConsoleMock: View {
    var prep: GlassPrepPhase

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 14) {
                toolbar
                HStack(spacing: 12) {
                    agentCard(name: "ChatGPT", tint: GlassInk.teal, checks: leftChecks)
                    routeGlyph
                        .frame(width: 48, height: 20)
                    agentCard(name: "Claude", tint: GlassInk.coral, checks: rightChecks)
                }
                footer
            }
        }
        .frame(width: 520)
    }

    /// The right side lags the left a step, the way a real staging pass
    /// works through one window at a time.
    private var leftChecks: [GlassCheckRow.Status] {
        switch prep {
        case .connecting: [.done, .working, .pending]
        case .arming: [.done, .done, .working]
        case .ready: [.done, .done, .done]
        }
    }

    private var rightChecks: [GlassCheckRow.Status] {
        switch prep {
        case .connecting: [.working, .pending, .pending]
        case .arming: [.done, .working, .pending]
        case .ready: [.done, .done, .done]
        }
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "bird.fill")
                    .font(.system(size: 10))
                Text("ERROL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.5)
            }
            Spacer()
            HStack(spacing: 7) {
                if prep == .ready {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(GlassInk.teal)
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i < progressDots
                                      ? AnyShapeStyle(.secondary)
                                      : AnyShapeStyle(.quaternary))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                Text(prep.statusText.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }

    private var progressDots: Int {
        switch prep {
        case .connecting: 1
        case .arming: 2
        case .ready: 3
        }
    }

    private func agentCard(name: String, tint: Color,
                           checks: [GlassCheckRow.Status]) -> some View {
        let ready = checks.allSatisfy { $0 == .done }
        let labels = ["Window found", "Front & visible", "Reply box armed"]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(ready ? 0.9 : 0.35), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(tint.opacity(ready ? 1 : 0.4))
                        .frame(width: 7, height: 7)
                }
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(ready ? "READY" : "PREP")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(ready ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
            }
            VStack(spacing: 6) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    GlassCheckRow(label: label, status: checks[i], tint: tint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    /// The relay route between the cards: dashed while staging, solid with
    /// the courier bead parked at center once the line is live.
    private var routeGlyph: some View {
        Canvas { ctx, size in
            let ready = prep == .ready
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 2, y: midY))
            line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            ctx.stroke(line, with: .color(.primary.opacity(ready ? 0.45 : 0.22)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                          dash: ready ? [] : [3, 4]))
            let cx = size.width / 2
            let dot = CGRect(x: cx - 4, y: midY - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: dot),
                     with: .color(.primary.opacity(ready ? 0.65 : 0.25)))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(MockRun.topic)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .capsule)

            HStack(spacing: 5) {
                Text(MockRun.shape)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            beginButton
        }
    }

    @ViewBuilder private var beginButton: some View {
        let label = Label(prep == .ready ? "Begin" : "Waiting",
                          systemImage: prep == .ready ? "play.fill" : "hourglass")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 4)
        if prep == .ready {
            Button {} label: { label }
                .buttonStyle(.glassProminent)
                .tint(GlassInk.teal)
        } else {
            Button {} label: { label.foregroundStyle(.tertiary) }
                .buttonStyle(.glass)
                .disabled(true)
        }
    }
}

// MARK: - Surface 2 · Glass companion (compact, in run)

/// The pane the console shrinks to during a run: two status tiles and one
/// prominent pause/resume control floating between them. The container
/// spacing is tight enough that the button visually pools with the tiles
/// as they approach — the Liquid Glass signature move.
struct GlassCompanionMock: View {
    var run: MockRun
    var paused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 14) {
                tile(name: "ChatGPT", tint: GlassInk.teal,
                     status: leftStatus, level: leftLevel,
                     sealed: run.leftSealed, alert: false)
                pauseButton
                tile(name: "Claude", tint: GlassInk.coral,
                     status: rightStatus, level: rightLevel,
                     sealed: run.rightSealed, alert: run.challenged)
            }
        }
    }

    private var leftStatus: String {
        if paused { return "Paused" }
        switch run.phase {
        case .thinking: return "Composing turn \(run.turn)"
        case .handoff: return "Handed off"
        case .complete: return "Signed off"
        default: return run.leftSealed ? "Signed off" : "Standing by"
        }
    }

    private var rightStatus: String {
        if paused { return "Paused" }
        switch run.phase {
        case .handoff: return "Receiving"
        case .waiting: return "Reading turn \(run.turn)"
        case .disagreement: return "Challenge open"
        case .firstSignoff, .complete: return "Signed off"
        default: return "Standing by"
        }
    }

    private var leftLevel: Int {
        if paused { return 0 }
        return run.leftComposing ? 3 : (run.delivering ? 2 : 1)
    }

    private var rightLevel: Int {
        if paused { return 0 }
        if run.challenged { return 4 }
        return run.rightArmed ? 3 : (run.delivering ? 2 : 1)
    }

    private func tile(name: String, tint: Color, status: String,
                      level: Int, sealed: Bool, alert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(paused ? 0.45 : 1))
                    .frame(width: 7, height: 7)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if sealed {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(tint)
                }
            }
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            GlassPulseBars(level: level, tint: alert ? GlassInk.amber : tint)
        }
        .padding(12)
        .frame(width: 132, alignment: .leading)
        .glassEffect(alert ? Glass.regular.tint(GlassInk.amber.opacity(0.32)) : Glass.regular,
                     in: .rect(cornerRadius: 16))
    }

    /// Resume is the tinted, inviting state; pause stays neutral glass so
    /// the button never nags while the run is healthy.
    private var pauseButton: some View {
        Button {} label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(paused ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(paused
                     ? Glass.regular.tint(GlassInk.teal.opacity(0.9)).interactive()
                     : Glass.regular.interactive(),
                     in: .circle)
    }
}

// MARK: - Previews

private struct GlassConsoleHarness: View {
    @State private var prep: GlassPrepPhase = .arming

    var body: some View {
        ZStack {
            GlassBackdrop()
            VStack(spacing: 22) {
                GlassConsoleMock(prep: prep)
                Picker("Prep", selection: $prep) {
                    ForEach(GlassPrepPhase.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            .padding(28)
        }
        .frame(width: 640, height: 440)
    }
}

private struct GlassCompanionHarness: View {
    @State private var phase: MockPhase = .thinking
    @State private var paused = false

    var body: some View {
        ZStack {
            GlassBackdrop()
            VStack(spacing: 22) {
                GlassCompanionMock(run: MockRun(phase: phase), paused: paused)
                VStack(spacing: 9) {
                    Picker("Phase", selection: $phase) {
                        ForEach(MockPhase.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 500)
                    Toggle("Paused", isOn: $paused)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(28)
        }
        .frame(width: 640, height: 360)
    }
}

#Preview("1 · Glass console (getting ready)") {
    GlassConsoleHarness()
}

#Preview("2 · Glass companion (in run)") {
    GlassCompanionHarness()
}

#Preview("Both surfaces") {
    ZStack {
        GlassBackdrop()
        VStack(spacing: 28) {
            GlassConsoleMock(prep: .arming)
            GlassCompanionMock(run: MockRun(phase: .thinking), paused: false)
        }
        .padding(32)
    }
    .frame(width: 660, height: 640)
}

#endif

// Second round of visual design studies, NOT wired into the app. Where
// DesignMockups.swift renders the directions from the two brainstorm docs,
// these three concepts are original takes on what running Errol actually
// feels like: you stage a conversation, hand over the machine, and watch.
// Each concept ships as a pair — a full default/config view, plus a small
// companion view that shows only the live interaction, for the mode where
// the UI shrinks out of the way during a run:
//
//   1. FieldStationMock / FieldStationTickerMock — Errol as a scientific
//      strip-chart recorder: honest to what the app is (an observer that
//      records two thinking machines). Two ink pens draw the run onto
//      scrolling chart paper; the artifact is the torn-off strip.
//   2. SingleLineMock / SingleLineRibbonMock — the relay's turn-taking
//      protocol made literal: a single-track railway worked by token (one
//      message ever in flight, exclusive right-of-way), reported on a
//      split-flap board and controlled from a lever frame.
//   3. MatineeMock / MatineeBalconyMock — honest to what the user is
//      during a run (an audience): a tiny proscenium stage with curtain,
//      footlights, two silhouette actors, and a bow at sign-off.
//
// All six views render from the shared MockRun in DesignMockups.swift so
// the concepts stay comparable phase by phase.

#if DEBUG

import SwiftUI

// MARK: - Concept 1 · Field Station (strip-chart recorder)

private enum StationInk {
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.885)
    static let grid = Color(red: 0.855, green: 0.815, blue: 0.70)
    static let olive = Color(red: 0.235, green: 0.245, blue: 0.20)
    static let oliveDeep = Color(red: 0.165, green: 0.175, blue: 0.14)
    static let brass = Color(red: 0.72, green: 0.575, blue: 0.30)
    static let cream = Color(red: 0.93, green: 0.90, blue: 0.82)
    static let teal = Color(red: 0.13, green: 0.44, blue: 0.41)
    static let coral = Color(red: 0.71, green: 0.34, blue: 0.22)
    static let stamp = Color(red: 0.42, green: 0.33, blue: 0.55)
    static let record = Color(red: 0.64, green: 0.20, blue: 0.15)
}

/// The chart itself: two pen traces over gridded paper, with an event
/// channel along the bottom margin. History is fixed; only the rightmost
/// stretch changes with the phase, the way a real recorder only ever
/// writes at the pen line.
private struct ChartPaper: View {
    var run: MockRun
    var compact = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(StationInk.paper))

            let vStep = compact ? w / 14 : w / 24
            var x: CGFloat = vStep
            var i = 1
            while x < w {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: h))
                ctx.stroke(p, with: .color(StationInk.grid.opacity(i % 4 == 0 ? 0.9 : 0.45)),
                           lineWidth: i % 4 == 0 ? 0.8 : 0.5)
                x += vStep; i += 1
            }
            var y: CGFloat = h / 8
            while y < h {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(p, with: .color(StationInk.grid.opacity(0.45)), lineWidth: 0.5)
                y += h / 8
            }

            let tealBase = h * 0.32
            let coralBase = h * 0.60
            let fresh = run.phase == .idle
            let amp: Double = compact ? 7 : 10

            // Composing bursts and delivery marks earlier in the run; the
            // final stretch (t > 0.76) is decided by the current phase.
            var tealBursts: [(Double, Double)] = fresh ? [] : [(0.04, 0.15), (0.36, 0.46), (0.62, 0.70)]
            let coralBursts: [(Double, Double)] = fresh ? [] : [(0.19, 0.30), (0.48, 0.58)]
            var spikes: [Double] = fresh ? [] : [0.155, 0.305, 0.465, 0.585, 0.705]
            var tealEnd: Double? = nil
            var coralEnd: Double? = nil
            switch run.phase {
            case .idle, .waiting:
                if run.phase == .waiting { spikes.append(0.90) }
            case .thinking:
                tealBursts.append((0.80, 1.0))
            case .handoff:
                tealBursts.append((0.74, 0.87))
                spikes.append(0.895)
            case .disagreement:
                spikes.append(0.79)
            case .firstSignoff:
                coralEnd = 0.90
            case .complete:
                tealEnd = 0.90
                coralEnd = 0.86
            }

            func burstEnvelope(_ t: Double, _ bursts: [(Double, Double)]) -> Double {
                for (a, b) in bursts where t >= a && t <= b {
                    return sin(.pi * (t - a) / (b - a))
                }
                return 0
            }

            let weaving = run.phase == .disagreement
            func penY(_ t: Double, teal: Bool) -> Double {
                var base = teal ? tealBase : coralBase
                if weaving, t > 0.78 {
                    let s = (t - 0.78) / 0.21
                    let mix = 0.5 - 0.5 * cos(s * .pi * 3)
                    let other = teal ? coralBase : tealBase
                    base += (other - base) * mix
                }
                let calm = sin(t * 47 + (teal ? 0 : 2.1)) * 1.1 + sin(t * 23 + (teal ? 1 : 4)) * 0.7
                let burst = burstEnvelope(t, teal ? tealBursts : coralBursts)
                    * sin(t * 260 + (teal ? 0 : 3)) * amp
                let rough = weaving && t > 0.78 ? sin(t * 300) * 2.5 : 0
                return base + calm + burst + rough
            }

            for teal in [true, false] {
                let end = (teal ? tealEnd : coralEnd) ?? 1.0
                var p = Path()
                var t = 0.0
                p.move(to: CGPoint(x: 0, y: penY(0, teal: teal)))
                while t <= end {
                    t += 3 / w
                    p.addLine(to: CGPoint(x: t * w, y: penY(min(t, end), teal: teal)))
                }
                ctx.stroke(p, with: .color(teal ? StationInk.teal : StationInk.coral),
                           style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                // A lifted pen leaves an end bar; the pen itself waits at
                // the right edge, nib hollow.
                let nibY = penY(end, teal: teal)
                if (teal ? tealEnd : coralEnd) != nil {
                    var bar = Path()
                    bar.move(to: CGPoint(x: end * w, y: nibY - 5))
                    bar.addLine(to: CGPoint(x: end * w, y: nibY + 5))
                    ctx.stroke(bar, with: .color(teal ? StationInk.teal : StationInk.coral),
                               lineWidth: 1.5)
                }
                let carriageY = (teal ? tealEnd : coralEnd) == nil
                    ? penY(1.0, teal: teal) : (teal ? tealBase : coralBase)
                var arm = Path()
                arm.move(to: CGPoint(x: w, y: carriageY))
                arm.addLine(to: CGPoint(x: w - 13, y: carriageY))
                ctx.stroke(arm, with: .color(StationInk.olive.opacity(0.8)), lineWidth: 2)
                let nib = CGRect(x: w - 17, y: carriageY - 3.5, width: 7, height: 7)
                if (teal ? tealEnd : coralEnd) == nil {
                    ctx.fill(Path(ellipseIn: nib),
                             with: .color(teal ? StationInk.teal : StationInk.coral))
                } else {
                    ctx.stroke(Path(ellipseIn: nib),
                               with: .color(teal ? StationInk.teal : StationInk.coral),
                               lineWidth: 1.2)
                }
            }

            // Event channel: a third pen in the margin blips once per
            // delivery — observable events only.
            let evY = h - (compact ? 7 : 10)
            var ev = Path()
            ev.move(to: CGPoint(x: 0, y: evY))
            for s in spikes.sorted() {
                ev.addLine(to: CGPoint(x: s * w - 2, y: evY))
                ev.addLine(to: CGPoint(x: s * w - 2, y: evY - 4))
                ev.addLine(to: CGPoint(x: s * w + 2, y: evY - 4))
                ev.addLine(to: CGPoint(x: s * w + 2, y: evY))
            }
            ev.addLine(to: CGPoint(x: w, y: evY))
            ctx.stroke(ev, with: .color(StationInk.stamp.opacity(0.75)), lineWidth: 1)

            func stamp(_ text: String, at cx: Double, y: CGFloat) {
                let label = Text(text)
                    .font(.system(size: compact ? 6 : 7, weight: .bold, design: .monospaced))
                    .foregroundColor(StationInk.stamp)
                let boxW = CGFloat(text.count) * (compact ? 5 : 6) + 8
                let rect = CGRect(x: cx * w - boxW / 2, y: y - 7, width: boxW, height: 14)
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 2),
                           with: .color(StationInk.stamp.opacity(0.8)), lineWidth: 1)
                ctx.draw(label, at: CGPoint(x: cx * w, y: y))
            }
            // In the ticker the corner chip already carries the word, so
            // the rubber stamps are full-size only.
            if run.phase == .disagreement && !compact { stamp("CHLG", at: 0.88, y: h * 0.14) }
            if run.phase == .firstSignoff && !compact { stamp("S/O 1", at: 0.90, y: h * 0.78) }
            if run.phase == .complete {
                if !compact { stamp("FIN 12T", at: 0.88, y: h * 0.14) }
                var tear = Path()
                var ty: CGFloat = 0
                tear.move(to: CGPoint(x: w * 0.965, y: 0))
                while ty < h {
                    ty += 6
                    tear.addLine(to: CGPoint(x: w * (ty.truncatingRemainder(dividingBy: 12) == 0 ? 0.965 : 0.955), y: ty))
                }
                ctx.stroke(tear, with: .color(StationInk.olive.opacity(0.5)), lineWidth: 1)
            }
            if fresh && !compact {
                ctx.draw(Text("READY — PAPER LOADED")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(StationInk.olive.opacity(0.5)),
                    at: CGPoint(x: w / 2, y: h / 2))
            }
        }
    }
}

/// Default/config mode: the full recording console — brass plate, subject
/// card, the live chart, and an instrument row for protocol, turns, ink,
/// and the record key.
struct FieldStationMock: View {
    var run: MockRun

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ERROL · FIELD RECORDING STATION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(StationInk.oliveDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(
                        LinearGradient(colors: [StationInk.brass.opacity(0.95),
                                                StationInk.brass.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)))
                Spacer()
                Text("OBS Nº 042")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(StationInk.cream.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SUBJECT — " + MockRun.topic)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(StationInk.oliveDeep)
                Text("PROTOCOL — \(MockRun.shape.uppercased()) · TWO SPECIMENS · CHATGPT (TEAL) / CLAUDE (CORAL)")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(StationInk.oliveDeep.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(StationInk.cream))

            ChartPaper(run: run)
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(StationInk.oliveDeep, lineWidth: 1.5))

            HStack(alignment: .bottom, spacing: 16) {
                HStack(spacing: 8) {
                    protocolSwitch("BRIEF", on: false)
                    protocolSwitch("DEBATE", on: true)
                    protocolSwitch("INTVW", on: false)
                    protocolSwitch("REVIEW", on: false)
                }
                Spacer()
                VStack(spacing: 3) {
                    Text(String(format: "%02d", run.turn))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(StationInk.cream)
                        .frame(width: 34, height: 20)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.55)))
                    consoleLabel("TURNS")
                }
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(StationInk.teal).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(StationInk.cream.opacity(0.4)))
                        Circle().fill(StationInk.coral).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(StationInk.cream.opacity(0.4)))
                    }
                    .frame(height: 20)
                    consoleLabel("INK")
                }
                VStack(spacing: 3) {
                    Button {} label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [StationInk.record,
                                                              StationInk.record.opacity(0.75)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 34, height: 34)
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                            Circle().stroke(.black.opacity(0.3), lineWidth: 2)
                                .frame(width: 26, height: 26)
                            if run.running {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(StationInk.cream)
                                    .frame(width: 10, height: 10)
                            } else {
                                Circle().fill(StationInk.cream).frame(width: 10, height: 10)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    consoleLabel(run.running ? "LIFT PENS" : "RECORD")
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(StationInk.olive))
        }
        .padding(14)
        .frame(width: 470)
        .background(RoundedRectangle(cornerRadius: 12).fill(StationInk.oliveDeep)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(StationInk.brass.opacity(0.45), lineWidth: 1))
    }

    private func protocolSwitch(_ label: String, on: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.black.opacity(0.4))
                    .frame(width: 10, height: 22)
                Circle()
                    .fill(on ? StationInk.brass : StationInk.cream.opacity(0.6))
                    .frame(width: 9, height: 9)
                    .offset(y: on ? -6 : 6)
            }
            consoleLabel(label)
        }
    }

    private func consoleLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(StationInk.cream.opacity(0.75))
    }
}

/// Companion mode: the ticker — a floating strip of live chart paper with
/// nothing but the pens, a REC tab, and one status word. This is the whole
/// UI while a run has the machine.
struct FieldStationTickerMock: View {
    var run: MockRun

    var body: some View {
        ChartPaper(run: run, compact: true)
            .frame(width: 300, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(StationInk.olive.opacity(0.7), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(run.running ? StationInk.record : StationInk.cream.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(run.running ? "REC" : (run.phase == .complete ? "END" : "RDY"))
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                    Text("T\(String(format: "%02d", run.turn))")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .opacity(0.7)
                }
                .foregroundColor(StationInk.cream)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(StationInk.olive))
                .offset(x: 7, y: 6)
            }
            .overlay(alignment: .topTrailing) {
                Text(shortStatus)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(StationInk.oliveDeep.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(StationInk.paper.opacity(0.92)))
                    .offset(x: -7, y: 6)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var shortStatus: String {
        switch run.phase {
        case .idle: "READY"
        case .thinking: "CHATGPT COMPOSING"
        case .handoff: "DELIVERY"
        case .waiting: "AT CLAUDE"
        case .disagreement: "CHALLENGE"
        case .firstSignoff: "SIGN-OFF 1 OF 2"
        case .complete: "COMPLETE"
        }
    }
}

// MARK: - Concept 2 · Single Line (railway token working)

private enum LineColors {
    static let enamel = Color(red: 0.10, green: 0.27, blue: 0.21)
    static let panel = Color(red: 0.14, green: 0.34, blue: 0.265)
    static let cream = Color(red: 0.93, green: 0.89, blue: 0.79)
    static let flap = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let brass = Color(red: 0.80, green: 0.64, blue: 0.31)
    static let arm = Color(red: 0.70, green: 0.22, blue: 0.17)
    static let amber = Color(red: 0.91, green: 0.65, blue: 0.24)
}

/// One row of a Solari split-flap board, padded to a fixed cell count so
/// the board never changes width.
private struct FlapRow: View {
    var text: String
    var cells = 24
    var cellSize = CGSize(width: 14, height: 19)

    var body: some View {
        HStack(spacing: 1.5) {
            let padded = text.uppercased().padding(toLength: cells, withPad: " ", startingAt: 0)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, ch in
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [LineColors.flap.opacity(0.85),
                                                      LineColors.flap],
                                             startPoint: .top, endPoint: .bottom))
                    Text(String(ch))
                        .font(.system(size: cellSize.height * 0.6,
                                      weight: .bold, design: .monospaced))
                        .foregroundColor(LineColors.cream)
                    Rectangle()
                        .fill(.black.opacity(0.55))
                        .frame(height: 1)
                }
                .frame(width: cellSize.width, height: cellSize.height)
            }
        }
    }
}

/// The block diagram: two stations, one track, one token. The token's
/// position IS the relay state — nothing moves unless it really moved.
private struct LineDiagram: View {
    var run: MockRun
    var compact = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lineY = h * (compact ? 0.62 : 0.58)
            let stationW: CGFloat = compact ? 34 : 64
            let stationH: CGFloat = compact ? 16 : 26

            func station(_ name: String, short: String, cx: CGFloat, lamp: Bool) {
                let rect = CGRect(x: cx - stationW / 2, y: lineY - stationH / 2,
                                  width: stationW, height: stationH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(LineColors.enamel))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                           with: .color(LineColors.cream), lineWidth: 1.2)
                ctx.draw(Text(compact ? short : name)
                    .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
                    .foregroundColor(LineColors.cream),
                    at: CGPoint(x: cx, y: lineY))
                let lampRect = CGRect(x: cx - 2.5, y: rect.minY - 8, width: 5, height: 5)
                ctx.fill(Path(ellipseIn: lampRect),
                         with: .color(lamp ? LineColors.amber : LineColors.cream.opacity(0.2)))
                if lamp {
                    ctx.stroke(Path(ellipseIn: lampRect.insetBy(dx: -2, dy: -2)),
                               with: .color(LineColors.amber.opacity(0.4)), lineWidth: 1)
                }
            }

            let leftX = stationW / 2 + 4
            let rightX = w - stationW / 2 - 4
            var track = Path()
            track.move(to: CGPoint(x: leftX, y: lineY))
            track.addLine(to: CGPoint(x: rightX, y: lineY))
            ctx.stroke(track, with: .color(LineColors.cream.opacity(0.8)), lineWidth: 1.5)
            for i in 1...3 {
                let bx = leftX + (rightX - leftX) * CGFloat(i) / 4
                var tick = Path()
                tick.move(to: CGPoint(x: bx, y: lineY - 3))
                tick.addLine(to: CGPoint(x: bx, y: lineY + 3))
                ctx.stroke(tick, with: .color(LineColors.cream.opacity(0.5)), lineWidth: 1)
            }

            station("CHATGPT", short: "G", cx: stationW / 2 + 2, lamp: run.leftComposing)
            station("CLAUDE", short: "C", cx: w - stationW / 2 - 2, lamp: run.rightArmed)

            // Semaphores: left = section entry, right = acceptance. An arm
            // raised 40° is clear; horizontal is danger. The challenge puts
            // the home signal at danger while the token stands mid-section.
            func semaphore(baseX: CGFloat, clear: Bool, mirrored: Bool) {
                let postTop = lineY - (compact ? 14 : 22)
                var post = Path()
                post.move(to: CGPoint(x: baseX, y: lineY - 4))
                post.addLine(to: CGPoint(x: baseX, y: postTop))
                ctx.stroke(post, with: .color(LineColors.cream.opacity(0.8)), lineWidth: 1.5)
                let len: CGFloat = compact ? 10 : 15
                let angle = clear ? Angle.degrees(mirrored ? 220 : -40) : Angle.degrees(mirrored ? 180 : 0)
                let tip = CGPoint(x: baseX + cos(angle.radians) * len,
                                  y: postTop + sin(angle.radians) * len)
                var arm = Path()
                arm.move(to: CGPoint(x: baseX, y: postTop))
                arm.addLine(to: tip)
                ctx.stroke(arm, with: .color(LineColors.arm),
                           style: StrokeStyle(lineWidth: compact ? 3 : 4.5, lineCap: .butt))
                let stripe = CGPoint(x: baseX + cos(angle.radians) * len * 0.75,
                                     y: postTop + sin(angle.radians) * len * 0.75)
                ctx.fill(Path(ellipseIn: CGRect(x: stripe.x - 1.5, y: stripe.y - 1.5,
                                                width: 3, height: 3)),
                         with: .color(LineColors.cream))
            }
            let entryClear = run.delivering
            let acceptClear = !run.challenged && run.phase != .complete
            semaphore(baseX: leftX + (compact ? 8 : 14), clear: entryClear, mirrored: false)
            semaphore(baseX: rightX - (compact ? 8 : 14), clear: acceptClear, mirrored: true)
            if run.challenged && !compact {
                ctx.draw(Text("◆ NOT ACCEPTED — CHALLENGE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(LineColors.amber),
                    at: CGPoint(x: w * 0.5, y: lineY + (compact ? 12 : 18)))
            }

            // The token: a brass hoop with its tag. At a station it hangs
            // on that platform's catcher (just clear of the box); in the
            // section it rides the line.
            let tokenX = leftX + (rightX - leftX)
                * min(max(run.courierFraction, 0.12), 0.88)
            let tokenY = lineY - (compact ? 8 : 11)
            let r: CGFloat = compact ? 4.5 : 6.5
            ctx.stroke(Path(ellipseIn: CGRect(x: tokenX - r, y: tokenY - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(LineColors.brass), lineWidth: compact ? 2 : 3)
            ctx.fill(Path(roundedRect: CGRect(x: tokenX + r * 0.5, y: tokenY + r * 0.5,
                                              width: 5, height: 7), cornerRadius: 1),
                     with: .color(LineColors.brass.opacity(0.85)))
            if run.phase == .complete {
                let safe = CGRect(x: tokenX - r - 4, y: tokenY - r - 4,
                                  width: r * 2 + 8, height: r * 2 + 8)
                ctx.stroke(Path(roundedRect: safe, cornerRadius: 2),
                           with: .color(LineColors.cream.opacity(0.7)), lineWidth: 1)
                if !compact {
                    ctx.draw(Text("TOKEN DEPOSITED")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(LineColors.cream.opacity(0.7)),
                        at: CGPoint(x: w * 0.5, y: lineY + 18))
                }
            }
        }
    }
}

/// Default/config mode: the signal box — split-flap board, block diagram,
/// a lever frame for the conversation shape, the subject blind, and the
/// dispatch plunger.
struct SingleLineMock: View {
    var run: MockRun

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                FlapRow(text: run.statusLine)
                FlapRow(text: "TURN \(String(format: "%02d", run.turn)) · \(MockRun.shape)")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35)))

            LineDiagram(run: run)
                .frame(height: 86)
                .background(RoundedRectangle(cornerRadius: 6).fill(LineColors.panel))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(LineColors.cream.opacity(0.25)))
                .overlay(alignment: .bottomTrailing) {
                    if run.phase == .complete { ticket }
                }

            HStack(alignment: .bottom, spacing: 14) {
                leverFrame
                VStack(spacing: 3) {
                    Text(MockRun.topic.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(LineColors.cream)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 3).fill(LineColors.flap))
                    boxLabel("SUBJECT BLIND")
                }
                VStack(spacing: 3) {
                    Button {} label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [LineColors.brass,
                                                              LineColors.brass.opacity(0.65)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 36, height: 36)
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                            Circle().stroke(.black.opacity(0.35), lineWidth: 1.5)
                                .frame(width: 27, height: 27)
                            Circle().fill(.black.opacity(0.25)).frame(width: 9, height: 9)
                        }
                    }
                    .buttonStyle(.plain)
                    boxLabel(run.running ? "ON LINE" : "DISPATCH")
                }
            }
        }
        .padding(14)
        .frame(width: 470)
        .background(RoundedRectangle(cornerRadius: 12).fill(LineColors.enamel)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(LineColors.brass.opacity(0.5), lineWidth: 1))
    }

    private var leverFrame: some View {
        HStack(spacing: 9) {
            lever("BRIEF", pulled: false)
            lever("DEBATE", pulled: true)
            lever("INTVW", pulled: false)
            lever("REVIEW", pulled: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3)))
    }

    private func lever(_ label: String, pulled: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.black.opacity(0.45))
                    .frame(width: 4, height: 12)
                Capsule()
                    .fill(pulled ? LineColors.brass : LineColors.cream.opacity(0.75))
                    .frame(width: 5, height: 26)
                    .overlay(Circle()
                        .fill(pulled ? LineColors.brass : LineColors.cream)
                        .frame(width: 8, height: 8), alignment: .top)
                    .rotationEffect(.degrees(pulled ? 16 : -10), anchor: .bottom)
            }
            .frame(width: 22, height: 32, alignment: .bottom)
            boxLabel(label)
        }
    }

    private var ticket: some View {
        VStack(spacing: 1) {
            Text("ERROL RY")
                .font(.system(size: 7, weight: .heavy, design: .serif))
            Text("SINGLE LINE · DEBATE")
                .font(.system(size: 6, weight: .medium, design: .serif))
            Text("12 TURNS — COMPLETE")
                .font(.system(size: 6, weight: .bold, design: .serif))
        }
        .foregroundColor(Color(red: 0.32, green: 0.24, blue: 0.16))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: 0.94, green: 0.86, blue: 0.70)))
        .overlay(RoundedRectangle(cornerRadius: 2)
            .stroke(Color(red: 0.32, green: 0.24, blue: 0.16).opacity(0.4)))
        .rotationEffect(.degrees(-3))
        .offset(x: -10, y: -8)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private func boxLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(LineColors.cream.opacity(0.7))
    }
}

/// Companion mode: the line ribbon — one word of split-flap, the track,
/// the token, and the two signals. The crispest possible answer to
/// "whose turn is it, and is anything stuck?"
struct SingleLineRibbonMock: View {
    var run: MockRun

    var body: some View {
        VStack(spacing: 4) {
            FlapRow(text: ribbonWord, cells: 10,
                    cellSize: CGSize(width: 10, height: 14))
            LineDiagram(run: run, compact: true)
                .frame(height: 34)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 10).fill(LineColors.enamel)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(LineColors.brass.opacity(0.5), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Text("T\(String(format: "%02d", run.turn))")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(LineColors.brass)
                .offset(x: -8, y: 8)
        }
    }

    private var ribbonWord: String {
        switch run.phase {
        case .idle: "READY"
        case .thinking: "COMPOSING"
        case .handoff: "ON LINE"
        case .waiting: "AT CLAUDE"
        case .disagreement: "CHALLENGE"
        case .firstSignoff: "SIGN-OFF"
        case .complete: "COMPLETE"
        }
    }
}

// MARK: - Concept 3 · Matinee (the smallest theater on your Mac)

private enum House {
    static let wall = Color(red: 0.10, green: 0.075, blue: 0.10)
    static let gold = Color(red: 0.80, green: 0.65, blue: 0.34)
    static let curtain = Color(red: 0.44, green: 0.11, blue: 0.15)
    static let curtainDeep = Color(red: 0.29, green: 0.055, blue: 0.09)
    static let backdrop = Color(red: 0.115, green: 0.13, blue: 0.20)
    static let backdropDeep = Color(red: 0.06, green: 0.065, blue: 0.11)
    static let boards = Color(red: 0.38, green: 0.26, blue: 0.17)
    static let lime = Color(red: 1.0, green: 0.92, blue: 0.75)
    static let actor = Color(red: 0.08, green: 0.07, blue: 0.11)
    static let teal = Color(red: 0.35, green: 0.68, blue: 0.64)
    static let coral = Color(red: 0.88, green: 0.55, blue: 0.42)
    static let card = Color(red: 0.93, green: 0.89, blue: 0.80)
}

/// The stage picture: curtain, backdrop, boards, footlights, and the two
/// silhouette actors. Everything the run does is stage business — a
/// spotlight to compose, a passed note to deliver, a face-off to
/// challenge, a bow to sign off.
private struct StageScene: View {
    var run: MockRun
    var compact = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let floorY = h * 0.80

            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [House.backdrop, House.backdropDeep]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: h - floorY)),
                     with: .linearGradient(
                        Gradient(colors: [House.boards, House.boards.opacity(0.6)]),
                        startPoint: CGPoint(x: 0, y: floorY),
                        endPoint: CGPoint(x: 0, y: h)))
            for i in 1...4 {
                var plank = Path()
                let py = floorY + (h - floorY) * CGFloat(i) / 5
                plank.move(to: CGPoint(x: 0, y: py))
                plank.addLine(to: CGPoint(x: w, y: py))
                ctx.stroke(plank, with: .color(.black.opacity(0.18)), lineWidth: 0.7)
            }

            let closed = run.phase == .idle
            let leftX = w * 0.34
            let rightX = w * 0.66

            func spotlight(x: CGFloat, strength: Double) {
                var cone = Path()
                cone.move(to: CGPoint(x: x - w * 0.03, y: 0))
                cone.addLine(to: CGPoint(x: x + w * 0.03, y: 0))
                cone.addLine(to: CGPoint(x: x + w * 0.10, y: floorY))
                cone.addLine(to: CGPoint(x: x - w * 0.10, y: floorY))
                cone.closeSubpath()
                ctx.fill(cone, with: .linearGradient(
                    Gradient(colors: [House.lime.opacity(0.16 * strength),
                                      House.lime.opacity(0.02)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - w * 0.11, y: floorY - 5,
                                                width: w * 0.22, height: 12)),
                         with: .color(House.lime.opacity(0.20 * strength)))
            }

            func actor(x: CGFloat, tall: Bool, tint: Color, active: Bool,
                       lean: Double, bow: Bool) {
                let bodyW: CGFloat = (tall ? 15 : 19) * (compact ? 0.7 : 1)
                let bodyH: CGFloat = (tall ? 42 : 36) * (compact ? 0.7 : 1)
                let headR: CGFloat = 6.5 * (compact ? 0.7 : 1)
                if active {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - bodyW * 2.2,
                                                    y: floorY - bodyH - headR * 4,
                                                    width: bodyW * 4.4,
                                                    height: bodyH + headR * 5)),
                             with: .radialGradient(
                                Gradient(colors: [tint.opacity(0.30), .clear]),
                                center: CGPoint(x: x, y: floorY - bodyH * 0.6),
                                startRadius: 0, endRadius: bodyW * 3))
                }
                ctx.drawLayer { layer in
                    layer.translateBy(x: x, y: floorY)
                    // A bow tips each silhouette toward the other — the
                    // mutual sign-off read as bowing to your scene partner.
                    layer.rotate(by: .degrees(bow ? (x < w / 2 ? 28 : -28) : lean))
                    let body = Path(roundedRect: CGRect(x: -bodyW / 2, y: -bodyH,
                                                        width: bodyW, height: bodyH),
                                    cornerRadius: bodyW / 2)
                    layer.fill(body, with: .color(House.actor))
                    let head = Path(ellipseIn: CGRect(x: -headR, y: -bodyH - headR * 2 + 2,
                                                      width: headR * 2, height: headR * 2))
                    layer.fill(head, with: .color(House.actor))
                    var rim = Path()
                    rim.addArc(center: CGPoint(x: 0, y: -bodyH - headR + 2), radius: headR,
                               startAngle: .degrees(x < w / 2 ? -60 : 200),
                               endAngle: .degrees(x < w / 2 ? 40 : 300), clockwise: false)
                    layer.stroke(rim, with: .color(tint.opacity(active ? 0.95 : 0.4)),
                                 lineWidth: 1.4)
                }
            }

            if !closed {
                let bothLit = run.challenged || run.phase == .complete
                if run.leftComposing || bothLit || run.delivering {
                    spotlight(x: leftX, strength: run.leftComposing ? 1 : 0.55)
                }
                if run.rightArmed || bothLit || run.delivering || run.phase == .firstSignoff {
                    spotlight(x: rightX, strength: run.challenged ? 1 : 0.55)
                }

                actor(x: leftX, tall: true, tint: House.teal,
                      active: run.leftComposing || run.challenged,
                      lean: run.challenged ? 7 : 0,
                      bow: run.phase == .complete)
                actor(x: rightX, tall: false, tint: House.coral,
                      active: run.rightArmed || run.challenged,
                      lean: run.challenged ? -7 : 0,
                      bow: run.rightSealed)

                if run.delivering {
                    var arc = Path()
                    arc.move(to: CGPoint(x: leftX + 12, y: floorY - 48))
                    arc.addQuadCurve(to: CGPoint(x: rightX - 12, y: floorY - 44),
                                     control: CGPoint(x: w / 2, y: floorY - 78))
                    ctx.stroke(arc, with: .color(House.card.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ctx.drawLayer { layer in
                        layer.translateBy(x: w / 2, y: floorY - 64)
                        layer.rotate(by: .degrees(12))
                        layer.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 8),
                                        cornerRadius: 1),
                                   with: .color(House.card))
                    }
                }

                if run.phase == .complete {
                    var stem = Path()
                    stem.move(to: CGPoint(x: w / 2 - 4, y: floorY + 8))
                    stem.addLine(to: CGPoint(x: w / 2 + 6, y: floorY + 5))
                    ctx.stroke(stem, with: .color(Color(red: 0.25, green: 0.42, blue: 0.24)),
                               lineWidth: 1.2)
                    ctx.fill(Path(ellipseIn: CGRect(x: w / 2 + 4, y: floorY + 2,
                                                    width: 5, height: 5)),
                             with: .color(Color(red: 0.62, green: 0.15, blue: 0.18)))
                }
            }

            // The curtain: closed before the run; a valance and legs while
            // playing; lowered partway over the bow.
            if closed {
                let stripeW = w / 14
                for i in 0..<14 {
                    let sx = CGFloat(i) * stripeW
                    ctx.fill(Path(CGRect(x: sx, y: 0, width: stripeW + 0.5, height: h)),
                             with: .linearGradient(
                                Gradient(colors: [i.isMultiple(of: 2) ? House.curtain : House.curtainDeep,
                                                  House.curtainDeep]),
                                startPoint: CGPoint(x: sx, y: h * 0.2),
                                endPoint: CGPoint(x: sx + stripeW, y: h)))
                }
                var split = Path()
                split.move(to: CGPoint(x: w / 2, y: 0))
                split.addLine(to: CGPoint(x: w / 2, y: h))
                ctx.stroke(split, with: .color(.black.opacity(0.4)), lineWidth: 2)
                ctx.fill(Path(CGRect(x: 0, y: h * 0.92, width: w, height: 2)),
                         with: .color(House.gold.opacity(0.5)))
            } else {
                let valanceH = run.phase == .complete ? h * 0.30 : h * 0.12
                var valance = Path()
                valance.move(to: CGPoint(x: 0, y: 0))
                valance.addLine(to: CGPoint(x: w, y: 0))
                valance.addLine(to: CGPoint(x: w, y: valanceH * 0.6))
                let scallops = 5
                for s in (0..<scallops).reversed() {
                    let x1 = w * CGFloat(s + 1) / CGFloat(scallops)
                    let x0 = w * CGFloat(s) / CGFloat(scallops)
                    valance.addQuadCurve(
                        to: CGPoint(x: x0, y: valanceH * 0.6),
                        control: CGPoint(x: (x0 + x1) / 2, y: valanceH * 1.35))
                }
                valance.closeSubpath()
                ctx.fill(valance, with: .linearGradient(
                    Gradient(colors: [House.curtain, House.curtainDeep]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: valanceH * 1.3)))
                for legX in [CGFloat(0), w - w * 0.055] {
                    ctx.fill(Path(CGRect(x: legX, y: 0, width: w * 0.055, height: h)),
                             with: .linearGradient(
                                Gradient(colors: [House.curtain, House.curtainDeep]),
                                startPoint: CGPoint(x: legX, y: 0),
                                endPoint: CGPoint(x: legX + w * 0.055, y: 0)))
                }
            }

            // The FIN card hangs in front of the half-lowered curtain.
            if run.phase == .complete {
                let card = CGRect(x: w / 2 - 21, y: h * 0.52 - 13, width: 42, height: 26)
                ctx.fill(Path(roundedRect: card, cornerRadius: 2), with: .color(House.card))
                ctx.draw(Text("FIN")
                    .font(.system(size: compact ? 9 : 11, weight: .bold, design: .serif))
                    .foregroundColor(House.wall),
                    at: CGPoint(x: w / 2, y: h * 0.52))
            }

            // Footlights on the apron, warmer while a challenge is on.
            let lights = compact ? 4 : 6
            for i in 0..<lights {
                let lx = w * (CGFloat(i) + 0.5) / CGFloat(lights)
                ctx.fill(Path(ellipseIn: CGRect(x: lx - 9, y: h - 8, width: 18, height: 12)),
                         with: .radialGradient(
                            Gradient(colors: [(run.challenged ? Color(red: 1.0, green: 0.72, blue: 0.35)
                                                              : House.lime).opacity(0.5), .clear]),
                            center: CGPoint(x: lx, y: h - 2),
                            startRadius: 0, endRadius: 11))
                ctx.fill(Path(CGRect(x: lx - 3, y: h - 3, width: 6, height: 3)),
                         with: .color(.black.opacity(0.7)))
            }

            // Before the curtain rises, the placard announces the bill.
            if closed && !compact {
                let bw = w * 0.46, bh = h * 0.34
                let board = CGRect(x: w / 2 - bw / 2, y: h * 0.38, width: bw, height: bh)
                for leg in [board.minX + 8, board.maxX - 8] {
                    var l = Path()
                    l.move(to: CGPoint(x: leg, y: board.maxY))
                    l.addLine(to: CGPoint(x: leg + (leg < w / 2 ? -7 : 7), y: h * 0.94))
                    ctx.stroke(l, with: .color(House.boards), lineWidth: 2.5)
                }
                ctx.fill(Path(roundedRect: board, cornerRadius: 3), with: .color(House.card))
                ctx.stroke(Path(roundedRect: board.insetBy(dx: 3, dy: 3), cornerRadius: 2),
                           with: .color(House.gold.opacity(0.7)), lineWidth: 1)
                ctx.draw(Text("TONIGHT · A \(MockRun.shape.uppercased())")
                    .font(.system(size: 7, weight: .semibold, design: .serif))
                    .foregroundColor(House.wall.opacity(0.7)),
                    at: CGPoint(x: w / 2, y: board.minY + 13))
                ctx.draw(Text(MockRun.topic)
                    .font(.system(size: 9, weight: .medium, design: .serif).italic())
                    .foregroundColor(House.wall),
                    at: CGPoint(x: w / 2, y: board.midY + 6))
            }
        }
    }
}

/// Default/config mode: the full house — gold proscenium, the stage, and a
/// front-of-house rail with the programme, the scene counter, and the
/// curtain pull.
struct MatineeMock: View {
    var run: MockRun

    var body: some View {
        VStack(spacing: 10) {
            Text(run.phase == .idle
                 ? "THE ERROL · TWICE DAILY"
                 : "NOW PLAYING — \(MockRun.topic.uppercased())")
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .tracking(1.8)
                .foregroundColor(House.gold)
                .lineLimit(1)

            StageScene(run: run)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(House.gold, lineWidth: 2.5))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .stroke(House.gold.opacity(0.35), lineWidth: 1)
                    .padding(-4))
                .overlay(alignment: .top) {
                    ZStack {
                        Circle().fill(House.wall).frame(width: 20, height: 20)
                        Circle().stroke(House.gold, lineWidth: 1.5).frame(width: 20, height: 20)
                        Text("E")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundColor(House.gold)
                    }
                    .offset(y: -10)
                }

            HStack(alignment: .center, spacing: 14) {
                programme
                Spacer()
                Text(run.phase == .complete ? "CURTAIN · 12 SCENES"
                     : "SCENE \(String(format: "%02d", run.turn))")
                    .font(.system(size: 9, weight: .semibold, design: .serif))
                    .tracking(1.5)
                    .foregroundColor(House.gold)
                Button {} label: {
                    Text(curtainLabel)
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundColor(House.wall)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(House.gold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: 470)
        .background(RoundedRectangle(cornerRadius: 14).fill(House.wall)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5))
    }

    private var programme: some View {
        HStack(spacing: 5) {
            ForEach(Array(["Brief", "Debate", "Interview"].enumerated()), id: \.offset) { i, name in
                let active = name == MockRun.shape
                Text(name)
                    .font(.system(size: 8, weight: active ? .bold : .medium, design: .serif))
                    .foregroundColor(House.wall.opacity(active ? 1 : 0.55))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 2)
                        .fill(House.card.opacity(active ? 1 : 0.55)))
                    .rotationEffect(.degrees(Double(i - 1) * 2))
                    .offset(y: active ? -2 : 0)
                    .shadow(color: .black.opacity(active ? 0.4 : 0.15), radius: 1, y: 1)
            }
        }
    }

    private var curtainLabel: String {
        switch run.phase {
        case .idle: "Curtain up"
        case .complete: "Playbill"
        default: "Curtain down"
        }
    }
}

/// Companion mode: the balcony view — just the arch and the stage picture,
/// with a scene tag in the corner. Nothing to operate; only the play.
struct MatineeBalconyMock: View {
    var run: MockRun

    var body: some View {
        StageScene(run: run, compact: true)
            .frame(width: 300, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(House.gold, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                Text("SC \(String(format: "%02d", run.turn))")
                    .font(.system(size: 7, weight: .semibold, design: .serif))
                    .tracking(1)
                    .foregroundColor(House.gold.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(House.wall.opacity(0.8)))
                    .offset(x: -7, y: -6)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Previews

/// One concept per preview, default mode above its companion mode, both
/// stepping through the same phase.
private struct Take2Harness<Full: View, Mini: View>: View {
    @State private var phase: MockPhase = .thinking
    @ViewBuilder var full: (MockRun) -> Full
    @ViewBuilder var mini: (MockRun) -> Mini

    var body: some View {
        VStack(spacing: 20) {
            full(MockRun(phase: phase))
            mini(MockRun(phase: phase))
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

#Preview("1 · Field Station") {
    Take2Harness(full: { FieldStationMock(run: $0) },
                 mini: { FieldStationTickerMock(run: $0) })
}

#Preview("2 · Single Line") {
    Take2Harness(full: { SingleLineMock(run: $0) },
                 mini: { SingleLineRibbonMock(run: $0) })
}

#Preview("3 · Matinee") {
    Take2Harness(full: { MatineeMock(run: $0) },
                 mini: { MatineeBalconyMock(run: $0) })
}

#Preview("All minis · phases") {
    Grid(horizontalSpacing: 16, verticalSpacing: 14) {
        ForEach([MockPhase.thinking, .handoff, .disagreement, .complete]) { p in
            GridRow {
                FieldStationTickerMock(run: MockRun(phase: p))
                SingleLineRibbonMock(run: MockRun(phase: p))
                MatineeBalconyMock(run: MockRun(phase: p))
            }
        }
    }
    .padding(24)
    .background(Color(red: 0.96, green: 0.955, blue: 0.945))
}

#endif

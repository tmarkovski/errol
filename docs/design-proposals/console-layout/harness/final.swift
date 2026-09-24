// The final console-layout spec's reference images: Direction A as merged
// with Codex's review, and its peer review's four refinements — surface and
// title before model details, the summary kept while paused with an honest
// "Show … window" row action, popover actions gated by the relay's actual
// hold, and outcome-specific endings — plus the More button ("App menu")
// in the top row. Static mocks from Perch's components; the copy is the
// app's own (RunReport, RunBlock) wherever the state already has some.

import AppKit
import SwiftUI

enum FStage: CaseIterable {
    case ready, choose, longTitles, running, pausePending, paused, queued, held,
         complete, stopped, interrupted
}

private let finalSurface = Color(white: 0.975)
private let finalBackdrop = Color(red: 0.925, green: 0.93, blue: 0.94)
private let green = Color(red: 0.2, green: 0.62, blue: 0.36)
private let orange = Color(red: 0.86, green: 0.55, blue: 0.12)
private let note = "Push on the pricing question before you wrap up."

/// The top row's stable trailing control in every stage: Settings, the run
/// log, and the other app-level commands. Accessible name "App menu".
struct MockMore: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(Perch.text(11, .semibold))
            .foregroundStyle(Perch.secondary)
            .frame(width: Perch.s(26), height: Perch.s(22))
            .background(RoundedRectangle(cornerRadius: Perch.s(7)).fill(Perch.well))
            .accessibilityLabel("App menu")
    }
}

/// One side's destination under the box: the surface, which never
/// truncates, then the title, truncated in the middle so similar titles
/// keep the ends that tell them apart, then a state only when the side has
/// one to report. The chevron says it opens the participant popover.
struct MockDestination: View {
    enum Tone { case normal, attention, problem }
    let surface: String?
    let title: String
    var state: String? = nil
    var tone: Tone = .normal
    let trailing: Bool

    var body: some View {
        HStack(spacing: Perch.s(4)) {
            if tone == .attention {
                Text(title).font(Perch.text(11.5, .medium)).foregroundStyle(Perch.accentText).lineLimit(1)
            } else {
                if let surface {
                    Text(surface).font(Perch.text(11.5, .medium)).foregroundStyle(Perch.secondary).fixedSize()
                    Text("\u{00B7}").font(Perch.text(11.5)).foregroundStyle(Perch.muted).fixedSize()
                }
                Text(title).font(Perch.text(11.5)).foregroundStyle(Perch.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let state {
                    Text("\u{00B7} \(state)").font(Perch.text(11.5, tone == .problem ? .medium : .regular))
                        .foregroundStyle(tone == .problem ? Perch.red : Perch.muted).fixedSize()
                }
            }
            Image(systemName: "chevron.down").font(Perch.text(8, .semibold))
                .foregroundStyle(tone == .attention ? Perch.accentText : Perch.muted)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

struct MockFinal: View {
    let stage: FStage

    private var composing: Bool { [.ready, .choose, .longTitles].contains(stage) }
    private var working: Bool { [.running, .pausePending, .queued].contains(stage) }

    var body: some View {
        HStack(spacing: PerchConsoleView.columnGap) {
            MockEnd(side: .chatgpt, state: chatgptBadge)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                topRow.frame(height: Perch.s(22))
                box
                destinations.frame(height: Perch.s(17)).padding(.horizontal, PerchPromptBox.textInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            MockEnd(side: .claude, state: claudeBadge, dim: working)
        }
        .padding(.horizontal, PerchConsoleView.endInset)
        .padding(.vertical, Perch.s(8))
        .frame(width: Perch.widgetWidth, height: Perch.widgetHeight)
        .background(Capsule().fill(finalSurface))
        .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var chatgptBadge: MockState {
        if stage == .choose { return .attention }
        return working ? .replying : .ready
    }

    private var claudeBadge: MockState {
        if stage == .held || stage == .interrupted { return .attention }
        return working ? .waiting : .ready
    }

    // MARK: The top row

    private var topRow: some View {
        HStack(spacing: Perch.s(10)) {
            if composing {
                MockMenuChip(icon: "arrow.right.circle", title: "ChatGPT starts", plain: true)
                MockMenuChip(icon: "flag.checkered", title: "Ends when both agree", plain: true)
                MockMenuChip(icon: "rectangle.split.2x1", title: "Windows side by side", plain: true)
            } else {
                Text("Whether to price by seat or by usage")
                    .font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                    .padding(.leading, Perch.s(4))
            }
            Spacer()
            MockMore()
        }
        .padding(.leading, PerchPromptBox.textInset - Perch.s(4))
        .padding(.trailing, Perch.s(7))
    }

    // MARK: The box

    @ViewBuilder private var box: some View {
        switch stage {
        case .ready, .choose, .longTitles:
            editor(text: stage == .longTitles ? "Critique the enterprise pricing tier" : "Pricing by seat or by usage",
                   reason: stage == .choose ? "Choose ChatGPT\u{2019}s conversation to start" : nil)
        case .running:
            panel(icon: speakerIcon, headline: Text("ChatGPT is replying\u{2026}"),
                  lines: [Text("Turn 5 of 10 \u{00B7} 0:03 \u{00B7} Note sent to Claude with turn 3")]) {
                runButtons(pauseEnabled: true)
            }
        case .pausePending:
            panel(icon: speakerIcon, headline: Text("Pausing after the current handoff\u{2026}"),
                  lines: [Text("ChatGPT is still replying \u{00B7} Turn 5 of 10 \u{00B7} 0:03")]) {
                runButtons(pauseEnabled: false)
            }
        case .queued:
            panel(icon: speakerIcon, headline: Text("ChatGPT is replying\u{2026}"),
                  lines: [Text("Note queued \u{00B7} goes to Claude with the next handoff").foregroundStyle(Perch.accentText)
                            + Text("   Clear note").foregroundStyle(Perch.secondary).fontWeight(.medium),
                          Text("\u{201C}\(note)\u{201D}")]) {
                runButtons(pauseEnabled: true)
            }
        case .held:
            panel(icon: AnyView(Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: Perch.s(18))).foregroundStyle(Perch.red)
                                    .frame(width: Perch.s(26))),
                  headline: Text("Paused: Claude\u{2019}s window isn\u{2019}t showing").foregroundStyle(Perch.red),
                  lines: [Text("It is minimized. Bring it back to continue, or Stop. Errol resumes when it is showing again.")]) {
                runButtons(pauseEnabled: true)
            }
        case .paused:
            noteEditor
        case .complete:
            panel(icon: AnyView(Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: Perch.s(20))).foregroundStyle(green).frame(width: Perch.s(26))),
                  headline: Text("Run complete"),
                  lines: [Text("6 replies relayed \u{00B7} ran 0:11 \u{00B7} both signed off")]) {
                PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") {}
            }
        case .stopped:
            panel(icon: AnyView(Image(systemName: "stop.circle")
                                    .font(.system(size: Perch.s(20))).foregroundStyle(Perch.secondary).frame(width: Perch.s(26))),
                  headline: Text("Run stopped"),
                  lines: [Text("4 replies relayed \u{00B7} ran 3:12")]) {
                PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") {}
            }
        case .interrupted:
            panel(icon: AnyView(Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: Perch.s(18))).foregroundStyle(orange).frame(width: Perch.s(26))),
                  headline: Text("Delivery to Claude interrupted"),
                  lines: [Text("5 replies relayed \u{00B7} ran 4:02 \u{00B7} focus was lost mid-send; check whether the message went")]) {
                PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") {}
            }
        }
    }

    private var speakerIcon: AnyView { AnyView(MockSmallIcon(side: .chatgpt)) }

    private func runButtons(pauseEnabled: Bool) -> some View {
        HStack(spacing: Perch.s(8)) {
            PerchRoundButton(title: stage == .queued ? "Edit note" : "Pause to steer", icon: "pause.fill") {}
                .disabled(!pauseEnabled)
            PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) {}
        }
    }

    /// The prompt as an editor: the only stage besides the paused note
    /// where the box holds a text cursor.
    private func editor(text: String, reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: Perch.s(13))).foregroundStyle(Perch.ink)
                .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
            Spacer(minLength: 0)
            HStack(spacing: Perch.s(8)) {
                if let reason {
                    Text(reason).font(Perch.text(11.5)).foregroundStyle(Perch.secondary).padding(.leading, Perch.s(5))
                }
                Spacer()
                MockStart(enabled: reason == nil)
            }
            .padding(.horizontal, Perch.s(7)).padding(.bottom, Perch.s(6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
        .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.chipEdge))
    }

    /// The paused note: a real editor with its cursor, once the relay has
    /// granted the hold.
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Perch.s(1)) {
                Rectangle().fill(Perch.accentText).frame(width: Perch.s(1.5), height: Perch.s(17))
                Text("A note for Claude with the next handoff\u{2026}")
                    .font(.system(size: Perch.s(13))).foregroundStyle(Perch.placeholder)
            }
            .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
            Spacer(minLength: 0)
            HStack(spacing: Perch.s(8)) {
                Text("Paused at turn 5 \u{00B7} Return or Esc resumes without a note")
                    .font(Perch.text(11)).foregroundStyle(Perch.muted).padding(.leading, Perch.s(5))
                Spacer()
                PerchCapsuleButton(title: "Resume", icon: "play.fill") {}
                PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") {}
            }
            .padding(.horizontal, Perch.s(7)).padding(.bottom, Perch.s(6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
        .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.accent.opacity(0.6), lineWidth: 1.5))
    }

    /// The recessed status panel: no text element, no cursor. The icon
    /// says whose turn it is or what kind of news this is; the headline
    /// what is happening or how the run ended; the lines the rest.
    private func panel(icon: AnyView, headline: Text, lines: [Text],
                       @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: Perch.s(12)) {
            icon
            VStack(alignment: .leading, spacing: Perch.s(3)) {
                headline.font(Perch.text(14, .medium)).foregroundStyle(Perch.ink).lineLimit(1)
                ForEach(lines.indices, id: \.self) { index in
                    lines[index].font(Perch.text(11)).foregroundStyle(Perch.muted)
                        .lineLimit(lines.count == 1 ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Perch.s(8))
            actions()
        }
        .padding(.leading, PerchPromptBox.textInset).padding(.trailing, Perch.s(7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.well))
    }

    // MARK: The destinations

    private var destinations: some View {
        HStack(spacing: Perch.s(16)) {
            switch stage {
            case .choose:
                MockDestination(surface: nil, title: "Choose one of 2 conversations", tone: .attention, trailing: false)
            case .longTitles:
                MockDestination(surface: "Work", title: "\u{201C}Pricing critique \u{2014} enterprise tier, second pass with finance\u{201D}",
                                trailing: false)
            default:
                MockDestination(surface: "Chat", title: "\u{201C}Pricing by seat or by usage\u{201D}", trailing: false)
            }
            switch stage {
            case .longTitles:
                MockDestination(surface: "Code", title: "\u{201C}Pricing critique \u{2014} enterprise tier, first pass\u{201D}",
                                trailing: true)
            case .held:
                MockDestination(surface: "Chat", title: "\u{201C}Naming ideas\u{201D}", state: "window minimized",
                                tone: .problem, trailing: true)
            case .interrupted:
                MockDestination(surface: "Chat", title: "\u{201C}Naming ideas\u{201D}", state: "check delivery",
                                tone: .problem, trailing: true)
            default:
                MockDestination(surface: "Chat", title: "\u{201C}Naming ideas\u{201D}", trailing: true)
            }
        }
    }
}

// MARK: - The summary window

/// A row of the summary: the model's line, a reply quoted whole (italic, in
/// quotes), or the human's note; and, on the row that has keyboard focus
/// or the pointer, its one action.
struct FinalRow: Identifiable {
    enum Kind { case gist, quoted, note }
    let id: Int
    let side: Speaker?
    let text: String
    var kind = Kind.gist
    var signsOff = false
    var action: String? = nil
}

private let finalRows: [FinalRow] = [
    FinalRow(id: 1, side: .chatgpt, text: "Favors per-seat pricing because buyers can predict the bill"),
    FinalRow(id: 2, side: .claude, text: "Holds that seats punish wide, light use and proposes capped usage pricing"),
    FinalRow(id: 3, side: .chatgpt, text: "Concedes the cap helps but proposes a per-seat floor plus usage"),
    FinalRow(id: 4, side: nil, text: note, kind: .note),
    FinalRow(id: 5, side: .claude, text: "Agrees with the hybrid if the allowance covers most teams"),
]

struct MockFinalSummary: View {
    let rows: [FinalRow]
    let count: String

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(4)) {
            HStack {
                Text("Conversation summary").font(Perch.text(11, .semibold)).foregroundStyle(Perch.secondary)
                Spacer()
                Text(count).font(Perch.text(10.5)).foregroundStyle(Perch.muted)
            }
            .padding(.bottom, Perch.s(2))
            ForEach(rows) { row in
                rowView(row, newest: row.id == rows.last?.id)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PerchPromptBox.textInset)
        .padding(.vertical, Perch.s(9))
        .frame(width: PerchConsoleView.promptBoxWidth(consoleWidth: Perch.widgetWidth), height: PerchTranscript.height,
               alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
        .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.chipEdge))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private func rowView(_ row: FinalRow, newest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
            Group {
                if let side = row.side {
                    MockMark(side: side)
                } else {
                    Image(systemName: "person.fill").font(Perch.text(10)).foregroundStyle(Perch.accentText)
                        .frame(width: Perch.s(12))
                }
            }
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Perch.s(1.5) }
            Group {
                switch row.kind {
                case .gist: Text(row.text)
                case .quoted:
                    HStack(spacing: 0) {
                        Text("\u{201C}").italic().fixedSize()
                        Text(row.text).italic().lineLimit(1).truncationMode(.tail)
                        Text("\u{201D}").italic().fixedSize()
                    }
                case .note: Text(row.text)
                }
            }
            .font(Perch.text(12)).foregroundStyle(newest && row.kind == .gist ? Perch.ink : Perch.secondary)
            .lineLimit(1)
            if row.kind == .note {
                Text("note to Claude").font(Perch.text(10.5)).foregroundStyle(Perch.muted)
                    .padding(.horizontal, Perch.s(5)).padding(.vertical, Perch.s(1))
                    .background(Capsule().fill(Perch.well)).fixedSize()
            }
            if row.signsOff {
                Text("\u{00B7} signs off").font(Perch.text(12)).foregroundStyle(Perch.muted).fixedSize()
            }
            Spacer(minLength: 0)
            if let action = row.action {
                HStack(spacing: Perch.s(4)) {
                    Image(systemName: "macwindow").font(Perch.text(9.5, .medium))
                    Text(action).font(Perch.text(10.5, .medium))
                }
                .foregroundStyle(Perch.ink)
                .padding(.horizontal, Perch.s(7)).frame(height: Perch.s(18))
                .background(Capsule().fill(Perch.paper))
                .overlay(Capsule().stroke(Perch.chipEdge))
                .fixedSize()
            }
        }
        .padding(.vertical, row.action == nil ? 0 : Perch.s(1))
        .background {
            if row.action != nil {
                RoundedRectangle(cornerRadius: Perch.s(6)).fill(Perch.well)
                    .padding(.horizontal, -Perch.s(5)).padding(.vertical, -Perch.s(1))
            }
        }
    }
}

// MARK: - The participant popover

/// What a click on an end icon or on its side's destination opens, in
/// every stage. Opening it changes nothing and activates no app; its
/// actions follow the run (the availability table in the spec).
struct MockFinalPopover: View {
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            HStack(spacing: Perch.s(8)) {
                MockSmallIcon(side: .chatgpt, size: Perch.s(24))
                Text("ChatGPT").font(Perch.text(13, .semibold)).foregroundStyle(Perch.ink)
                Spacer()
                if running {
                    Image(systemName: "ellipsis.circle.fill").font(.system(size: Perch.s(12))).foregroundStyle(Perch.accent)
                    Text("Replying").font(Perch.text(11)).foregroundStyle(Perch.accentText)
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: Perch.s(12))).foregroundStyle(green)
                    Text("Ready").font(Perch.text(11)).foregroundStyle(Perch.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Perch.s(2)) {
                Text("\u{201C}Pricing by seat or by usage\u{201D}").font(Perch.text(12.5, .medium)).foregroundStyle(Perch.ink)
                Text("Chat \u{00B7} 5.6 Sol High \u{00B7} continues this chat").font(Perch.text(11)).foregroundStyle(Perch.secondary)
            }
            Text("Errol writes into this window, whatever conversation it shows when a message is due.")
                .font(Perch.text(11)).foregroundStyle(Perch.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Perch.s(8)) {
                PerchCapsuleButton(title: "Show window", style: .secondary, icon: "macwindow") {}
                    .disabled(running)
                PerchCapsuleButton(title: "Choose another\u{2026}", style: .secondary, icon: "arrow.left.arrow.right") {}
                    .disabled(running)
            }
            if running {
                Text("Pause to show this window. The destination can change once the run ends.")
                    .font(Perch.text(10.5)).foregroundStyle(Perch.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Perch.s(14))
        .frame(width: Perch.s(322), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Perch.s(14)).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: Perch.s(14)).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Color.white).frame(width: Perch.s(14), height: Perch.s(14))
                .rotationEffect(.degrees(45))
                .offset(x: Perch.s(40), y: -Perch.s(6))
        }
        .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
    }
}

// MARK: - Rendering

@MainActor
func renderFinal(outDir: String) {
    func frame(_ view: some View, height: CGFloat) -> some View {
        VStack { view; Spacer(minLength: 0) }
            .padding(36)
            .frame(width: Perch.widgetWidth + 72, height: height + 72, alignment: .top)
            .background(finalBackdrop)
    }
    func size(_ height: CGFloat) -> CGSize { CGSize(width: Perch.widgetWidth + 72, height: height + 72) }
    let h = Perch.widgetHeight
    let runH = h + PerchTranscript.gap + PerchTranscript.height
    func withSummary(_ stage: FStage, _ rows: [FinalRow], _ count: String) -> some View {
        VStack(spacing: PerchTranscript.gap) {
            MockFinal(stage: stage)
            MockFinalSummary(rows: rows, count: count)
        }
    }

    let running = Array(finalRows)
    var paused = Array(finalRows.dropFirst())
    paused.append(FinalRow(id: 6, side: .chatgpt, text: "Agreed on the 80th percentile. Let\u{2019}s draft the pricing page next.",
                           kind: .quoted, action: "Show ChatGPT window"))
    var complete = Array(finalRows.dropFirst(2))
    complete.append(FinalRow(id: 6, side: .chatgpt, text: "Agreed on the 80th percentile. Let\u{2019}s draft the pricing page next.",
                             kind: .quoted, signsOff: true))
    complete.append(FinalRow(id: 7, side: .claude, text: "Drafts pricing page copy with three tiers and a calculator",
                             signsOff: true, action: "Show Claude window"))
    var interrupted = Array(finalRows.dropFirst())
    interrupted.append(FinalRow(id: 6, side: .chatgpt, text: "Agreed on the 80th percentile. Let\u{2019}s draft the pricing page next.",
                                kind: .quoted))

    render("01-ready", frame(MockFinal(stage: .ready), height: h), size: size(h), settle: 0.8)
    render("02-choose-destination", frame(MockFinal(stage: .choose), height: h), size: size(h), settle: 0.4)
    render("03-long-titles", frame(MockFinal(stage: .longTitles), height: h), size: size(h), settle: 0.4)
    render("04-running", frame(withSummary(.running, running, "4 replies so far"), height: runH), size: size(runH), settle: 0.5)
    render("05-pause-pending", frame(withSummary(.pausePending, running, "4 replies so far"), height: runH),
           size: size(runH), settle: 0.4)
    render("06-paused", frame(withSummary(.paused, paused, "5 replies so far"), height: runH), size: size(runH), settle: 0.4)
    let beforeNote = running.filter { $0.kind != .note }
    render("07-note-queued", frame(withSummary(.queued, beforeNote, "4 replies so far"), height: runH), size: size(runH), settle: 0.4)
    render("08-held", frame(withSummary(.held, running, "4 replies so far"), height: runH), size: size(runH), settle: 0.4)
    render("09-finished-complete", frame(withSummary(.complete, complete, "6 replies"), height: runH),
           size: size(runH), settle: 0.4)
    render("10-finished-stopped", frame(withSummary(.stopped, running, "4 replies"), height: runH),
           size: size(runH), settle: 0.4)
    render("11-finished-interrupted", frame(withSummary(.interrupted, interrupted, "5 replies"), height: runH),
           size: size(runH), settle: 0.4)
    let popH = h + Perch.s(190)
    render("12-participant-popover",
           frame(VStack(alignment: .leading, spacing: Perch.s(12)) {
               MockFinal(stage: .ready)
               MockFinalPopover(running: false).padding(.leading, Perch.s(18))
           }, height: popH), size: size(popH), settle: 0.5)
    render("13-participant-popover-running",
           frame(VStack(alignment: .leading, spacing: Perch.s(12)) {
               MockFinal(stage: .running)
               MockFinalPopover(running: true).padding(.leading, Perch.s(18))
           }, height: popH), size: size(popH), settle: 0.5)
}

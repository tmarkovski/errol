// Static mockups of two alternative console layouts, drawn with Perch's own
// pieces (avatars, marks, palette, buttons) so they compare directly with
// the current console's renders. Not wired to a controller: the content is
// the preview engine's pricing conversation, hard-coded.

import AppKit
import SwiftUI

// MARK: - Shared bits

private let chatgptID = config.chatgptBundleID
private let claudeID = config.claudeBundleID

private let gists = [
    (Speaker.chatgpt, "Favors per-seat pricing because buyers can predict the bill"),
    (.claude, "Holds that seats punish wide, light use and proposes capped usage pricing"),
    (.chatgpt, "Concedes the cap helps but proposes a per-seat floor plus usage"),
    (.claude, "Agrees with the hybrid if the allowance covers most teams"),
]

struct MockMark: View {
    let side: Speaker
    var size: CGFloat = Perch.s(12)
    var color: Color = Perch.secondary

    var body: some View {
        if let mark = AppIcons.mark(forBundleID: side == .chatgpt ? chatgptID : claudeID) {
            Image(nsImage: mark).renderingMode(.template).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit).frame(width: size, height: size).foregroundStyle(color)
        }
    }
}

enum MockState { case ready, attention, replying, waiting }

/// A small state badge for an icon's corner: a check, an attention mark,
/// or the replying dots' accent ring.
struct MockBadge: View {
    let state: MockState
    var body: some View {
        ZStack {
            Circle().fill(Perch.paper).frame(width: Perch.s(17), height: Perch.s(17))
            switch state {
            case .ready:
                Image(systemName: "checkmark.circle.fill").font(.system(size: Perch.s(15)))
                    .foregroundStyle(Color(red: 0.2, green: 0.62, blue: 0.36))
            case .attention:
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: Perch.s(15)))
                    .foregroundStyle(Color(red: 0.86, green: 0.55, blue: 0.12))
            case .replying:
                Image(systemName: "ellipsis.circle.fill").font(.system(size: Perch.s(15)))
                    .foregroundStyle(Perch.accent)
            case .waiting:
                Image(systemName: "clock.fill").font(.system(size: Perch.s(12)))
                    .foregroundStyle(Perch.muted)
            }
        }
    }
}

/// A labeled menu button that shows its current value: what the options
/// look like when they are on the console instead of behind a right-click.
struct MockMenuChip: View {
    let icon: String
    let title: String
    var plain = false
    var body: some View {
        HStack(spacing: Perch.s(4)) {
            Image(systemName: icon).font(Perch.text(10.5, .medium))
            Text(title).font(Perch.text(11.5))
            Image(systemName: "chevron.down").font(Perch.text(8, .semibold)).foregroundStyle(Perch.muted)
        }
        .foregroundStyle(Perch.secondary)
        .padding(.horizontal, plain ? Perch.s(4) : Perch.s(8))
        .frame(height: Perch.s(22))
        .background(RoundedRectangle(cornerRadius: Perch.s(7)).fill(plain ? Color.clear : Perch.well))
    }
}

/// Send, naming the recipient in words, with its mark.
struct MockSend: View {
    let recipient: Speaker
    var enabled = true
    var body: some View {
        HStack(spacing: Perch.s(6)) {
            Text("Send to \(recipient == .chatgpt ? "ChatGPT" : "Claude")").font(Perch.text(12, .medium))
            MockMark(side: recipient, size: Perch.s(13), color: enabled ? Perch.onAccent : Perch.secondary)
        }
        .foregroundStyle(enabled ? Perch.onAccent : Perch.secondary)
        .padding(.horizontal, Perch.s(13))
        .frame(height: Perch.s(29))
        .background(RoundedRectangle(cornerRadius: Perch.controlCorner).fill(enabled ? Perch.accent : Perch.well))
        .overlay(RoundedRectangle(cornerRadius: Perch.controlCorner).stroke(enabled ? .clear : Perch.chipEdge))
    }
}

/// Who goes first, as its own labeled swap control.
struct MockSwap: View {
    var body: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(Perch.text(11, .semibold))
            .foregroundStyle(Perch.secondary)
            .frame(width: Perch.s(29), height: Perch.s(29))
            .background(RoundedRectangle(cornerRadius: Perch.controlCorner).fill(Perch.well))
            .overlay(RoundedRectangle(cornerRadius: Perch.controlCorner).stroke(Perch.chipEdge))
    }
}

private func surface(dark: Bool = false) -> Color { Color(white: 0.975) }
private let backdrop = Color(red: 0.925, green: 0.93, blue: 0.94)

// MARK: - Direction A: keep the ends, give the sides words

/// An end of the capsule: the icon, its state badge, and the app's name,
/// which always fits.
struct MockEnd: View {
    let side: Speaker
    let state: MockState
    var dim = false
    var body: some View {
        VStack(spacing: Perch.s(4)) {
            PerchAvatar(bundleID: side == .chatgpt ? chatgptID : claudeID, initial: "", feather: .gray)
                .opacity(dim ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) { MockBadge(state: state).offset(x: Perch.s(5), y: Perch.s(5)) }
            Text(side == .chatgpt ? "ChatGPT" : "Claude")
                .font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .frame(height: Perch.s(17))
        }
        .frame(width: Perch.participantWidth)
    }
}

/// One side's half of the line under the box: its conversation and model,
/// or what it needs, with the chevron that says it opens the chooser.
struct MockSideLine: View {
    let title: String
    let detail: String?
    var attention = false
    let alignment: HorizontalAlignment

    var body: some View {
        HStack(spacing: Perch.s(4)) {
            if attention {
                Text(title).font(Perch.text(11.5, .medium)).foregroundStyle(Perch.accentText)
            } else {
                (Text(title).foregroundStyle(Perch.secondary)
                 + Text(detail.map { " \u{00B7} \($0)" } ?? "").foregroundStyle(Perch.muted))
                    .font(Perch.text(11.5))
            }
            Image(systemName: "chevron.down").font(Perch.text(8, .semibold))
                .foregroundStyle(attention ? Perch.accentText : Perch.muted)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

enum AStage { case ready, choose, running, paused, finished }

struct MockA: View {
    let stage: AStage

    var body: some View {
        HStack(spacing: PerchConsoleView.columnGap) {
            MockEnd(side: .chatgpt, state: chatgptState, dim: false)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                topLine.frame(height: Perch.s(22))
                box
                bottomLine.frame(height: Perch.s(17)).padding(.horizontal, PerchPromptBox.textInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            MockEnd(side: .claude, state: claudeState, dim: stage == .running)
        }
        .padding(.horizontal, PerchConsoleView.endInset)
        .padding(.vertical, Perch.s(8))
        .frame(width: Perch.widgetWidth, height: Perch.widgetHeight)
        .background(Capsule().fill(surface()))
        .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var chatgptState: MockState {
        switch stage {
        case .ready, .paused, .finished: .ready
        case .choose: .attention
        case .running: .replying
        }
    }
    private var claudeState: MockState { stage == .running ? .waiting : .ready }

    @ViewBuilder private var topLine: some View {
        switch stage {
        case .ready, .choose:
            HStack(spacing: Perch.s(10)) {
                MockMenuChip(icon: "flag.checkered", title: "Ends when both agree", plain: true)
                MockMenuChip(icon: "rectangle.split.2x1", title: "Windows side by side", plain: true)
                Spacer()
            }
            .padding(.leading, PerchPromptBox.textInset - Perch.s(4))
        case .running, .paused, .finished:
            Text("Whether to price by seat or by usage")
                .font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .padding(.horizontal, PerchPromptBox.textInset)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder private var box: some View {
        switch stage {
        case .ready, .choose:
            VStack(alignment: .leading, spacing: 0) {
                Text("Pricing by seat or by usage")
                    .font(.system(size: Perch.s(13))).foregroundStyle(Perch.ink)
                    .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
                Spacer(minLength: 0)
                HStack(spacing: Perch.s(6)) {
                    Spacer()
                    MockSwap()
                    MockSend(recipient: .chatgpt, enabled: stage == .ready)
                }
                .padding(.horizontal, Perch.s(7)).padding(.bottom, Perch.s(6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
            .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.chipEdge))
        case .running:
            // Not a field: a recessed display of what is happening, so it
            // never looks like somewhere to type.
            HStack(spacing: Perch.s(12)) {
                MockMark(side: .chatgpt, size: Perch.s(20), color: Perch.accentText)
                VStack(alignment: .leading, spacing: Perch.s(3)) {
                    Text("ChatGPT is replying\u{2026}").font(Perch.text(14, .medium)).foregroundStyle(Perch.ink)
                    Text("Turn 5 of 10 \u{00B7} 0:03 \u{00B7} Note sent to Claude with turn 3")
                        .font(Perch.text(11)).foregroundStyle(Perch.muted)
                }
                Spacer()
                PerchRoundButton(title: "Pause to steer", icon: "pause.fill") {}
                PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) {}
            }
            .padding(.leading, PerchPromptBox.textInset).padding(.trailing, Perch.s(7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.well))
        case .finished:
            HStack(spacing: Perch.s(12)) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: Perch.s(20)))
                    .foregroundStyle(Color(red: 0.2, green: 0.62, blue: 0.36))
                VStack(alignment: .leading, spacing: Perch.s(3)) {
                    Text("Run complete").font(Perch.text(14, .medium)).foregroundStyle(Perch.ink)
                    Text("Both signed off after 6 replies \u{00B7} 0:11").font(Perch.text(11)).foregroundStyle(Perch.muted)
                }
                Spacer()
                PerchCapsuleButton(title: "New topic", icon: "arrow.counterclockwise") {}
            }
            .padding(.leading, PerchPromptBox.textInset).padding(.trailing, Perch.s(7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.well))
        case .paused:
            VStack(alignment: .leading, spacing: 0) {
                Text("A note for Claude with the next handoff\u{2026}")
                    .font(.system(size: Perch.s(13))).foregroundStyle(Perch.placeholder)
                    .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
                Spacer(minLength: 0)
                HStack(spacing: Perch.s(8)) {
                    Text("Paused \u{00B7} Turn 5 of 10 \u{00B7} Nothing is being copied or sent")
                        .font(Perch.text(11)).foregroundStyle(Perch.muted)
                        .padding(.leading, Perch.s(5))
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
    }

    @ViewBuilder private var bottomLine: some View {
        HStack(spacing: Perch.s(16)) {
            if stage == .choose {
                MockSideLine(title: "Choose one of 2 conversations", detail: nil, attention: true, alignment: .leading)
            } else {
                MockSideLine(title: "\u{201C}Pricing by seat or by usage\u{201D}", detail: "5.6 Sol High", alignment: .leading)
            }
            MockSideLine(title: "\u{201C}Naming ideas\u{201D}", detail: "Fable 5 Extra", alignment: .trailing)
        }
    }
}

// MARK: - Direction B: one card, the route across the top

/// A participant as a labeled chip: icon, name and state, conversation,
/// surface and model. Mirrored on the right.
struct MockChip: View {
    let side: Speaker
    let conversation: String
    let model: String
    let state: MockState
    var stateText: String
    var attention = false
    var trailing: Bool { side == .claude }

    var body: some View {
        HStack(spacing: Perch.s(10)) {
            if !trailing { icon }
            VStack(alignment: trailing ? .trailing : .leading, spacing: Perch.s(1.5)) {
                HStack(spacing: Perch.s(5)) {
                    if trailing { stateLabel }
                    Text(side == .chatgpt ? "ChatGPT" : "Claude").font(Perch.text(12.5, .semibold)).foregroundStyle(Perch.ink)
                    if !trailing { stateLabel }
                }
                HStack(spacing: Perch.s(3)) {
                    Text(conversation).font(Perch.text(11.5))
                        .foregroundStyle(attention ? Perch.accentText : Perch.secondary)
                        .fontWeight(attention ? .medium : .regular)
                    Image(systemName: "chevron.down").font(Perch.text(7.5, .semibold))
                        .foregroundStyle(attention ? Perch.accentText : Perch.muted)
                }
                Text(model).font(Perch.text(10.5)).foregroundStyle(Perch.muted)
            }
            .lineLimit(1)
            if trailing { icon }
        }
    }

    private var icon: some View {
        PerchAvatar(bundleID: side == .chatgpt ? chatgptID : claudeID, initial: "", feather: .gray)
            .scaleEffect(0.78)
            .frame(width: Perch.s(38), height: Perch.s(38))
            .opacity(state == .waiting ? 0.6 : 1)
    }

    private var stateLabel: some View {
        HStack(spacing: Perch.s(3)) {
            switch state {
            case .ready:
                Circle().fill(Color(red: 0.2, green: 0.62, blue: 0.36)).frame(width: Perch.s(6), height: Perch.s(6))
            case .attention:
                Circle().fill(Color(red: 0.86, green: 0.55, blue: 0.12)).frame(width: Perch.s(6), height: Perch.s(6))
            case .replying:
                HStack(spacing: Perch.s(2)) {
                    ForEach(0..<3) { i in Circle().fill(Perch.accentText).opacity(i == 1 ? 1 : 0.35)
                        .frame(width: Perch.s(3.5), height: Perch.s(3.5)) }
                }
            case .waiting:
                EmptyView()
            }
            Text(stateText).font(Perch.text(10.5)).foregroundStyle(state == .replying ? Perch.accentText : Perch.muted)
        }
    }
}

enum BStage { case ready, choose, running, paused, finished }

struct MockB: View {
    let stage: BStage
    static let width: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, Perch.s(16)).padding(.vertical, Perch.s(12))
            Rectangle().fill(Perch.hairline).frame(height: 1)
            content
            Rectangle().fill(Perch.hairline).frame(height: 1)
            footer.padding(.horizontal, Perch.s(14)).frame(height: Perch.s(48))
        }
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: Perch.s(20)).fill(surface()))
        .overlay(RoundedRectangle(cornerRadius: Perch.s(20)).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var header: some View {
        HStack(spacing: Perch.s(8)) {
            MockChip(side: .chatgpt,
                     conversation: stage == .choose ? "Choose a conversation" : "\u{201C}Pricing by seat or by usage\u{201D}",
                     model: "Chat \u{00B7} 5.6 Sol High",
                     state: chatgptState, stateText: chatgptText, attention: stage == .choose)
            Spacer(minLength: Perch.s(8))
            route
            Spacer(minLength: Perch.s(8))
            MockChip(side: .claude, conversation: "\u{201C}Naming ideas\u{201D}", model: "Chat \u{00B7} Fable 5 Extra",
                     state: claudeState, stateText: claudeText)
        }
    }

    private var chatgptState: MockState {
        switch stage { case .ready, .finished, .paused: .ready; case .choose: .attention; case .running: .replying }
    }
    private var chatgptText: String {
        switch stage { case .ready: "Ready"; case .choose: "2 open"; case .running: "Replying"; case .paused: "Reply ready"; case .finished: "Signed off" }
    }
    private var claudeState: MockState { stage == .running || stage == .paused ? .waiting : .ready }
    private var claudeText: String {
        switch stage { case .running: "Waiting"; case .paused: "Next"; case .finished: "Signed off"; default: "Ready" }
    }

    /// Who goes first, drawn as the direction of the relay, with the swap
    /// beside it while it can still change.
    private var route: some View {
        VStack(spacing: Perch.s(3)) {
            HStack(spacing: 0) {
                Rectangle().fill(Perch.chipEdge).frame(width: Perch.s(34), height: 1)
                Image(systemName: stage == .running || stage == .paused || stage == .finished ? "arrow.left.arrow.right" : "arrow.right")
                    .font(Perch.text(10, .semibold)).foregroundStyle(Perch.secondary)
                    .frame(width: Perch.s(24), height: Perch.s(24))
                    .background(Circle().fill(Perch.well))
                    .overlay(Circle().stroke(Perch.chipEdge))
                Rectangle().fill(Perch.chipEdge).frame(width: Perch.s(34), height: 1)
            }
            Text(stage == .running || stage == .paused ? "Turn 5 of 10 \u{00B7} 0:03" : stage == .finished ? "6 replies \u{00B7} 0:11" : "ChatGPT goes first \u{00B7} click to swap")
                .font(Perch.text(10.5)).foregroundStyle(Perch.muted)
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .ready, .choose:
            Text("Pricing by seat or by usage")
                .font(.system(size: Perch.s(13))).foregroundStyle(Perch.ink)
                .frame(maxWidth: .infinity, minHeight: Perch.s(56), alignment: .topLeading)
                .padding(.horizontal, Perch.s(16)).padding(.vertical, Perch.s(12))
                .background(Perch.paper)
        case .running, .paused, .finished:
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                ForEach(Array(gists.enumerated()), id: \.offset) { index, entry in
                    row(entry.0, entry.1, newest: stage == .running && index == gists.count - 1)
                    if index == 2 {
                        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
                            Image(systemName: "person.fill").font(Perch.text(10)).foregroundStyle(Perch.accentText)
                                .frame(width: Perch.s(12))
                            Text("Push on the pricing question before you wrap up.").font(Perch.text(12)).foregroundStyle(Perch.secondary)
                            Text("note to Claude").font(Perch.text(10.5)).foregroundStyle(Perch.muted)
                                .padding(.horizontal, Perch.s(5)).padding(.vertical, Perch.s(1))
                                .background(Capsule().fill(Perch.well))
                        }
                    }
                }
                if stage == .finished {
                    row(.chatgpt, "Agreed on the 80th percentile; let's draft the pricing page next", newest: false, signsOff: true)
                    row(.claude, "Drafts pricing page copy with three tiers and a calculator", newest: true, signsOff: true)
                } else if stage == .paused {
                    row(.chatgpt, "Agreed on the 80th percentile. Let's draft the pricing page next.", newest: true)
                    Text("A note for Claude with the next handoff\u{2026}")
                        .font(.system(size: Perch.s(13))).foregroundStyle(Perch.placeholder)
                        .frame(maxWidth: .infinity, minHeight: Perch.s(40), alignment: .topLeading)
                        .padding(.horizontal, Perch.s(10)).padding(.vertical, Perch.s(8))
                        .background(RoundedRectangle(cornerRadius: Perch.s(10)).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: Perch.s(10)).stroke(Perch.accent.opacity(0.6), lineWidth: 1.5))
                        .padding(.top, Perch.s(6))
                } else {
                    HStack(spacing: Perch.s(7)) {
                        MockMark(side: .chatgpt, size: Perch.s(12), color: Perch.accentText)
                        Text("Replying\u{2026}").font(Perch.text(12)).foregroundStyle(Perch.accentText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, Perch.s(16)).padding(.vertical, Perch.s(12))
            .background(Perch.paper)
        }
    }

    private func row(_ side: Speaker, _ text: String, newest: Bool, signsOff: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
            MockMark(side: side).alignmentGuide(.firstTextBaseline) { $0[.bottom] - Perch.s(1.5) }
            Text(text).font(Perch.text(12)).foregroundStyle(newest ? Perch.ink : Perch.secondary).lineLimit(1)
            if signsOff { Text("\u{00B7} signs off").font(Perch.text(12)).foregroundStyle(Perch.muted) }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: Perch.s(8)) {
            switch stage {
            case .ready, .choose:
                MockMenuChip(icon: "flag.checkered", title: "Ends when both agree")
                MockMenuChip(icon: "rectangle.split.2x1", title: "Windows side by side")
                Spacer()
                MockSend(recipient: .chatgpt, enabled: stage == .ready)
            case .running:
                Text("ChatGPT is replying\u{2026}").font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                Text("Pause before typing in either app").font(Perch.text(11)).foregroundStyle(Perch.muted)
                Spacer()
                PerchCapsuleButton(title: "Pause to steer", icon: "pause.fill") {}
                PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) {}
            case .paused:
                Text("Paused").font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                Text("Nothing is being copied or sent").font(Perch.text(11)).foregroundStyle(Perch.muted)
                Spacer()
                PerchCapsuleButton(title: "Resume", icon: "play.fill") {}
                PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") {}
            case .finished:
                Text("Run complete").font(Perch.text(12.5, .semibold)).foregroundStyle(Perch.ink)
                Text("both signed off after 6 replies \u{00B7} 0:11").font(Perch.text(11.5)).foregroundStyle(Perch.secondary)
                Spacer()
                PerchCapsuleButton(title: "New topic", icon: "arrow.counterclockwise") {}
            }
        }
    }
}

// MARK: - Rendering

@MainActor
func renderMocks(outDir: String) {
    func frame(_ view: some View, width: CGFloat, height: CGFloat) -> some View {
        VStack { view; Spacer(minLength: 0) }
            .padding(36)
            .frame(width: width + 72, height: height + 72, alignment: .top)
            .background(backdrop)
    }
    let aHeight = Perch.widgetHeight
    render("A1-ready", frame(MockA(stage: .ready), width: Perch.widgetWidth, height: aHeight),
           size: CGSize(width: Perch.widgetWidth + 72, height: aHeight + 72), settle: 0.8)
    render("A2-choose", frame(MockA(stage: .choose), width: Perch.widgetWidth, height: aHeight),
           size: CGSize(width: Perch.widgetWidth + 72, height: aHeight + 72), settle: 0.5)

    // The running mock keeps today's transcript window under it.
    let engine = PerchPreviewEngine(pace: .seconds(120), turn: 5)
    let controller = quick(connectedController(engine))
    controller.start()
    pump(0.5)
    play(engine, replies: 4)
    pump(1.5)
    let runHeight = aHeight + PerchTranscript.gap + PerchTranscript.height
    render("A3-running",
           frame(VStack(spacing: PerchTranscript.gap) {
               MockA(stage: .running)
               PerchTranscript(controller: controller)
                   .frame(width: PerchConsoleView.promptBoxWidth(consoleWidth: Perch.widgetWidth),
                          height: PerchTranscript.height)
                   .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
           }, width: Perch.widgetWidth, height: runHeight),
           size: CGSize(width: Perch.widgetWidth + 72, height: runHeight + 72), settle: 1.5)
    render("A4-paused", frame(MockA(stage: .paused), width: Perch.widgetWidth, height: aHeight),
           size: CGSize(width: Perch.widgetWidth + 72, height: aHeight + 72), settle: 0.5)

    // Finished keeps today's transcript window too, from a run played to
    // its mutual sign-off.
    let endEngine = PerchPreviewEngine(pace: .milliseconds(500), signOffAt: 5)
    let ended = quick(connectedController(endEngine))
    ended.start()
    pumpUntil(60) { ended.stage == .finished }
    pump(1.5)
    render("A5-finished",
           frame(VStack(spacing: PerchTranscript.gap) {
               MockA(stage: .finished)
               PerchTranscript(controller: ended)
                   .frame(width: PerchConsoleView.promptBoxWidth(consoleWidth: Perch.widgetWidth),
                          height: PerchTranscript.height)
                   .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
           }, width: Perch.widgetWidth, height: runHeight),
           size: CGSize(width: Perch.widgetWidth + 72, height: runHeight + 72), settle: 1.5)

    for (name, stage, height) in [("B1-ready", BStage.ready, 200.0), ("B2-choose", .choose, 200.0),
                                  ("B3-running", .running, 290.0), ("B4-finished", .finished, 300.0),
                                  ("B5-paused", .paused, 350.0)] {
        render(name, frame(MockB(stage: stage), width: MockB.width, height: height),
               size: CGSize(width: MockB.width + 72, height: height + 72), settle: 0.5)
    }
}

// MARK: - Converged: Direction A with Codex's review folded in

enum CStage { case ready, choose, running, paused, finished }

/// The primary action names the process it starts, not only its first
/// delivery (Codex's point); who starts is chosen on the line above.
struct MockStart: View {
    var enabled = true
    var body: some View {
        HStack(spacing: Perch.s(6)) {
            Image(systemName: "play.fill").font(Perch.text(10.5, .semibold))
            Text("Start relay").font(Perch.text(12, .medium))
        }
        .foregroundStyle(enabled ? Perch.onAccent : Perch.secondary)
        .padding(.horizontal, Perch.s(13))
        .frame(height: Perch.s(29))
        .background(RoundedRectangle(cornerRadius: Perch.controlCorner).fill(enabled ? Perch.accent : Perch.well))
        .overlay(RoundedRectangle(cornerRadius: Perch.controlCorner).stroke(enabled ? .clear : Perch.chipEdge))
    }
}

/// The app's own icon at a small size, so the running panel shows the
/// same face as the capsule's end rather than a different mark.
struct MockSmallIcon: View {
    let side: Speaker
    var size: CGFloat = Perch.s(26)
    var body: some View {
        PerchAvatar(bundleID: side == .chatgpt ? chatgptID : claudeID, initial: "", feather: .gray)
            .scaleEffect(size / Perch.s(46))
            .frame(width: size, height: size)
    }
}

struct MockConverged: View {
    let stage: CStage

    var body: some View {
        HStack(spacing: PerchConsoleView.columnGap) {
            MockEnd(side: .chatgpt, state: chatgptState)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                topLine.frame(height: Perch.s(22))
                box
                bottomLine.frame(height: Perch.s(17)).padding(.horizontal, PerchPromptBox.textInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            MockEnd(side: .claude, state: claudeState, dim: stage == .running)
        }
        .padding(.horizontal, PerchConsoleView.endInset)
        .padding(.vertical, Perch.s(8))
        .frame(width: Perch.widgetWidth, height: Perch.widgetHeight)
        .background(Capsule().fill(surface()))
        .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var chatgptState: MockState {
        switch stage { case .choose: .attention; case .running: .replying; default: .ready }
    }
    private var claudeState: MockState { stage == .running ? .waiting : .ready }

    @ViewBuilder private var topLine: some View {
        switch stage {
        case .ready, .choose:
            HStack(spacing: Perch.s(10)) {
                MockMenuChip(icon: "arrow.right.circle", title: "ChatGPT starts", plain: true)
                MockMenuChip(icon: "flag.checkered", title: "Ends when both agree", plain: true)
                MockMenuChip(icon: "rectangle.split.2x1", title: "Windows side by side", plain: true)
                Spacer()
            }
            .padding(.leading, PerchPromptBox.textInset - Perch.s(4))
        case .running, .paused, .finished:
            Text("Whether to price by seat or by usage")
                .font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .padding(.horizontal, PerchPromptBox.textInset)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func display(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.leading, PerchPromptBox.textInset).padding(.trailing, Perch.s(7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.well))
    }

    @ViewBuilder private var box: some View {
        switch stage {
        case .ready, .choose:
            VStack(alignment: .leading, spacing: 0) {
                Text("Pricing by seat or by usage")
                    .font(.system(size: Perch.s(13))).foregroundStyle(Perch.ink)
                    .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
                Spacer(minLength: 0)
                HStack(spacing: Perch.s(8)) {
                    if stage == .choose {
                        // The reason stands beside the action it holds back.
                        Text("Choose ChatGPT\u{2019}s conversation to start")
                            .font(Perch.text(11.5)).foregroundStyle(Perch.secondary)
                            .padding(.leading, Perch.s(5))
                    }
                    Spacer()
                    MockStart(enabled: stage == .ready)
                }
                .padding(.horizontal, Perch.s(7)).padding(.bottom, Perch.s(6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
            .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.chipEdge))
        case .running:
            display {
                HStack(spacing: Perch.s(12)) {
                    MockSmallIcon(side: .chatgpt)
                    VStack(alignment: .leading, spacing: Perch.s(3)) {
                        Text("ChatGPT is replying\u{2026}").font(Perch.text(14, .medium)).foregroundStyle(Perch.ink)
                        Text("Turn 5 of 10 \u{00B7} 0:03 \u{00B7} Note sent to Claude with turn 3")
                            .font(Perch.text(11)).foregroundStyle(Perch.muted)
                    }
                    Spacer()
                    PerchRoundButton(title: "Pause to steer", icon: "pause.fill") {}
                    PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) {}
                }
            }
        case .paused:
            VStack(alignment: .leading, spacing: 0) {
                Text("A note for Claude with the next handoff\u{2026}")
                    .font(.system(size: Perch.s(13))).foregroundStyle(Perch.placeholder)
                    .padding(.horizontal, PerchPromptBox.textInset).padding(.top, Perch.s(8))
                Spacer(minLength: 0)
                HStack(spacing: Perch.s(8)) {
                    Text("Paused at turn 5 \u{00B7} Return sends it \u{00B7} Esc resumes without one")
                        .font(Perch.text(11)).foregroundStyle(Perch.muted)
                        .padding(.leading, Perch.s(5))
                    Spacer()
                    PerchCapsuleButton(title: "Resume", icon: "play.fill") {}
                    PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") {}
                }
                .padding(.horizontal, Perch.s(7)).padding(.bottom, Perch.s(6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
            .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.accent.opacity(0.6), lineWidth: 1.5))
        case .finished:
            display {
                HStack(spacing: Perch.s(12)) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: Perch.s(20)))
                        .foregroundStyle(Color(red: 0.2, green: 0.62, blue: 0.36))
                    VStack(alignment: .leading, spacing: Perch.s(3)) {
                        Text("Run complete").font(Perch.text(14, .medium)).foregroundStyle(Perch.ink)
                        Text("Both signed off after 6 replies \u{00B7} 0:11")
                            .font(Perch.text(11)).foregroundStyle(Perch.muted)
                    }
                    Spacer()
                    PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") {}
                }
            }
        }
    }

    @ViewBuilder private var bottomLine: some View {
        HStack(spacing: Perch.s(16)) {
            if stage == .choose {
                MockSideLine(title: "Choose one of 2 conversations", detail: nil, attention: true, alignment: .leading)
            } else {
                MockSideLine(title: "\u{201C}Pricing by seat or by usage\u{201D}", detail: "5.6 Sol High", alignment: .leading)
            }
            MockSideLine(title: "\u{201C}Naming ideas\u{201D}", detail: "Fable 5 Extra", alignment: .trailing)
        }
    }
}

/// The window under the capsule, labeled for what it is: the model's
/// one-line account of each reply, with a reply quoted whole marked as a
/// quotation, and the human's note tagged with where it went.
struct MockSummaryWindow: View {
    let finished: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(5)) {
            HStack {
                Text("Conversation summary").font(Perch.text(11, .semibold)).foregroundStyle(Perch.secondary)
                Spacer()
                Text(finished ? "6 replies \u{00B7} click a line to open that chat" : "4 replies so far")
                    .font(Perch.text(10.5)).foregroundStyle(Perch.muted)
            }
            .padding(.bottom, Perch.s(2))
            ForEach(Array(gists.enumerated()).filter { !finished || $0.offset >= 2 }, id: \.offset) { index, entry in
                row(entry.0, Text(entry.1), newest: !finished && index == gists.count - 1)
                if index == 2 {
                    HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
                        Image(systemName: "person.fill").font(Perch.text(10)).foregroundStyle(Perch.accentText)
                            .frame(width: Perch.s(12))
                        Text("Push on the pricing question before you wrap up.").font(Perch.text(12)).foregroundStyle(Perch.secondary)
                        Text("note to Claude").font(Perch.text(10.5)).foregroundStyle(Perch.muted)
                            .padding(.horizontal, Perch.s(5)).padding(.vertical, Perch.s(1))
                            .background(Capsule().fill(Perch.well))
                    }
                }
            }
            if finished {
                row(.chatgpt, Text("\u{201C}Agreed on the 80th percentile. Let's draft the pricing page next.\u{201D}").italic(),
                    newest: false, signsOff: true)
                row(.claude, Text("Drafts pricing page copy with three tiers and a calculator"), newest: true, signsOff: true)
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

    private func row(_ side: Speaker, _ text: Text, newest: Bool, signsOff: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
            MockMark(side: side).alignmentGuide(.firstTextBaseline) { $0[.bottom] - Perch.s(1.5) }
            text.font(Perch.text(12)).foregroundStyle(newest ? Perch.ink : Perch.secondary).lineLimit(1)
            if signsOff { Text("\u{00B7} signs off").font(Perch.text(12)).foregroundStyle(Perch.muted) }
        }
    }
}

/// What a click on an end icon (or on its side's line) opens: the side's
/// details and its actions, the same popover whatever state the side is in.
struct MockParticipantPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            HStack(spacing: Perch.s(8)) {
                MockSmallIcon(side: .chatgpt, size: Perch.s(24))
                Text("ChatGPT").font(Perch.text(13, .semibold)).foregroundStyle(Perch.ink)
                Spacer()
                Circle().fill(Color(red: 0.2, green: 0.62, blue: 0.36)).frame(width: Perch.s(7), height: Perch.s(7))
                Text("Ready").font(Perch.text(11)).foregroundStyle(Perch.secondary)
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
                PerchCapsuleButton(title: "Choose another\u{2026}", style: .secondary, icon: "arrow.left.arrow.right") {}
            }
        }
        .padding(Perch.s(14))
        .frame(width: Perch.s(322), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Perch.s(14)).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: Perch.s(14)).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
        .overlay(alignment: .topLeading) {
            // The popover's arrow, pointing up at the icon.
            Rectangle().fill(Color.white).frame(width: Perch.s(14), height: Perch.s(14))
                .rotationEffect(.degrees(45))
                .offset(x: Perch.s(40), y: -Perch.s(6))
        }
        .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
    }
}

@MainActor
func renderConverged(outDir: String) {
    func frame(_ view: some View, width: CGFloat, height: CGFloat) -> some View {
        VStack { view; Spacer(minLength: 0) }
            .padding(36)
            .frame(width: width + 72, height: height + 72, alignment: .top)
            .background(backdrop)
    }
    let w = Perch.widgetWidth, h = Perch.widgetHeight
    let size = CGSize(width: w + 72, height: h + 72)
    render("converged-1-ready", frame(MockConverged(stage: .ready), width: w, height: h), size: size, settle: 0.8)
    render("converged-2-choose", frame(MockConverged(stage: .choose), width: w, height: h), size: size, settle: 0.5)
    let runH = h + PerchTranscript.gap + PerchTranscript.height
    let runSize = CGSize(width: w + 72, height: runH + 72)
    render("converged-3-running",
           frame(VStack(spacing: PerchTranscript.gap) { MockConverged(stage: .running); MockSummaryWindow(finished: false) },
                 width: w, height: runH), size: runSize, settle: 0.8)
    render("converged-4-paused", frame(MockConverged(stage: .paused), width: w, height: h), size: size, settle: 0.5)
    render("converged-5-finished",
           frame(VStack(spacing: PerchTranscript.gap) { MockConverged(stage: .finished); MockSummaryWindow(finished: true) },
                 width: w, height: runH), size: runSize, settle: 0.8)
    let popH = h + Perch.s(170)
    render("converged-6-participant",
           frame(VStack(alignment: .leading, spacing: Perch.s(12)) {
               MockConverged(stage: .ready)
               MockParticipantPopover().padding(.leading, Perch.s(18))
           }, width: w, height: popH),
           size: CGSize(width: w + 72, height: popH + 72), settle: 0.8)
}

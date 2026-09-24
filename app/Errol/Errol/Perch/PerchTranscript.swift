// The run's transcript, in a window of its own under the console
// (MenuBarController.transcriptPanel): each reply as a line beside the
// mark of the app that wrote it, summed up by the on-device model
// (ReplySummarizer), and each note the human sent beside a person, in the
// order the conversation took them in. The window is shaped like the
// prompt box — the same paper, corner, and insets, as wide as the box
// and centered under it, as tall as the console — and it behaves like the
// box: the lines start at the top, the newest at the bottom, and once
// they overflow they scroll, right up to the window's edge, following the
// newest line unless the reader has scrolled up to an older one. A
// reply's own words stand in italics, on one line, until the model's
// sentence replaces them; an older line's full text is its tooltip. It
// shows from the run's start, with only a placeholder until the first
// reply, through the ending, until New topic.

import SwiftUI

struct PerchTranscript: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the newest line is in view. A line landing, or the sentence
    /// taking an opening's place, scrolls the transcript to itself only
    /// then; a reader who has scrolled up to an older line is left there.
    @State private var followsNewest = true
    /// Whether the transcript is scrolling itself to the newest line, so
    /// the scroll's own motion is not read as the reader's.
    @State private var scrollingToNewest = false

    /// The window's height: the console's, so the two stand as a pair.
    /// Room for seven lines, or six with the newest taking two.
    static let height = Perch.widgetHeight
    /// The gap between the capsule's edge and the window.
    static let gap = Perch.s(10)
    /// The lines' inset from the window's top and bottom edges, the
    /// prompt's own; it scrolls away with the lines, so a scrolled line
    /// runs to the edge.
    private static let endInset = PerchPromptBox.verticalInset + GrowingTextEditor.insetHeight
    private static let lineSpacing = Perch.s(4)
    private static let follow = Animation.easeOut(duration: 0.35)
    /// A new line's landing: it rises into place from a little under
    /// where it stops, fading in, overshoots a few points, and settles.
    /// The scroll that follows it is a plain ease, so the bounce is the
    /// line's own. (Rubber-banding at the ends is AppKit's, on a trackpad.)
    private static let landing = Animation.spring(duration: 0.55, bounce: 0.45)
    private static let rise = Perch.s(24)

    /// Where the reader is in the lines, from the scroll view's geometry:
    /// the top of what shows, and how much of the lines lies below it.
    private struct Extent: Equatable {
        var top: CGFloat
        var below: CGFloat
    }

    var body: some View {
        let entries = controller.transcript
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.lineSpacing) {
                    ForEach(entries) { entry in
                        PerchTranscriptRow(controller: controller, entry: entry,
                                           isNewest: entry.id == entries.last?.id)
                            .id(entry.id)
                            .transition(reduceMotion ? .opacity
                                        : .asymmetric(insertion: .offset(y: Self.rise).combined(with: .opacity),
                                                      removal: .opacity))
                    }
                }
                .padding(.vertical, Self.endInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(reduceMotion ? Perch.fade : Self.landing, value: entries.map(\.id))
            }
            .onScrollGeometryChange(for: Extent.self) { geometry in
                Extent(top: geometry.visibleRect.minY,
                       below: geometry.contentSize.height - geometry.visibleRect.maxY)
            } action: { old, new in
                // Only a scroll moves the top. A line landing or growing
                // moves what lies below, and whether that is followed is
                // for the reader's last position to say.
                guard !scrollingToNewest, new.top != old.top else { return }
                followsNewest = new.below <= Self.lineSpacing
            }
            .onChange(of: entries) { _, entries in
                guard followsNewest, let newest = entries.last else { return }
                scrollingToNewest = true
                withAnimation(reduceMotion ? nil : Self.follow) {
                    proxy.scrollTo(newest.id, anchor: .bottom)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    scrollingToNewest = false
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if entries.isEmpty {
                Text("Each reply lands here, summed up in a line.")
                    .font(Perch.text(13))
                    .foregroundStyle(Perch.placeholder)
                    .lineLimit(1)
                    .padding(.vertical, Self.endInset)
                    .transition(.opacity)
            }
        }
        .animation(Perch.fade, value: entries.isEmpty)
        // The box's inset: its text starts here too. The lines' top and
        // bottom insets are inside the scrolling, so it reaches the edges.
        .padding(.horizontal, PerchPromptBox.textInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: PerchPromptBox.corner).fill(Perch.paper))
        .overlay(RoundedRectangle(cornerRadius: PerchPromptBox.corner).stroke(Perch.chipEdge, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The conversation so far")
    }
}

/// One line of the transcript: whose it is, what it says, whether it
/// signed off, and for a note, where it stands.
private struct PerchTranscriptRow: View {
    let controller: RelayController
    let entry: TranscriptEntry
    let isNewest: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
            icon
                .frame(width: Perch.s(12), height: Perch.s(12))
                .accessibilityLabel(author)
                // The mark sits on the first line's text, not above it.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Perch.s(1.5) }
            Text(entry.text)
                .font(Perch.text(12))
                .italic(entry.verbatim)
                .foregroundStyle(ink)
                // The model's sentence may run to a second line; a reply's
                // own words get one, as a quotation, not a reading.
                .lineLimit(entry.verbatim ? 1 : 2)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(Perch.fade, value: entry.text)
                .perchShimmer(active: entry.summarizing)
                .help(entry.text)
            if entry.author == .human {
                tag
            } else if entry.signsOff {
                Text("\u{00B7} signs off")
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var author: String {
        switch entry.author {
        case .side(let side): controller.appName(side)
        case .human: "You"
        }
    }

    /// The newest line reads in the box's ink; the ones before it step
    /// back. A reply's own words, in italics on one line, sit a step
    /// lighter than a sentence on it would — lighter still, under the
    /// busy shimmer, while the model writes that sentence — so the
    /// transcript reads as the model's account, with the replies quoted
    /// only where it has none.
    private var ink: Color {
        if entry.summarizing { return Perch.muted }
        if entry.verbatim { return isNewest ? Perch.secondary : Perch.muted }
        return isNewest ? Perch.ink : Perch.secondary
    }

    @ViewBuilder private var icon: some View {
        switch entry.author {
        case .side(let side):
            let bundleID = side == .chatgpt ? config.chatgptBundleID : config.claudeBundleID
            if let mark = AppIcons.mark(forBundleID: bundleID) {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Perch.secondary)
            } else {
                Text(String(controller.appName(side).prefix(1)))
                    .font(Perch.text(10, .semibold))
                    .foregroundStyle(Perch.secondary)
            }
        case .human:
            Image(systemName: "person.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Perch.accentText)
        }
    }

    /// Where a note stands, after it, kept whole while the note truncates:
    /// on its way, or how its handoff went. A note still queued is the
    /// prompt box's to show (PerchRunLine), since it is not yet part of
    /// the conversation; its echo to the other side is the ending's to
    /// tell (PerchReceiptLine).
    @ViewBuilder private var tag: some View {
        let recipient = entry.recipient.map(controller.appName)
        Group {
            switch entry.delivery {
            case .sending?:
                Text(recipient.map { "Sending to \($0)\u{2026}" } ?? "Sending\u{2026}")
                    .foregroundStyle(Perch.accentText)
            case .sent?:
                Text(recipient.map { "to \($0)" } ?? "Sent")
                    .foregroundStyle(Perch.muted)
            case .unconfirmed?:
                Text(recipient.map { "to \($0) \u{00B7} unconfirmed" } ?? "Unconfirmed")
                    .foregroundStyle(Perch.muted)
            case .notSent?:
                Text("Not sent")
                    .foregroundStyle(Perch.red)
            case nil:
                EmptyView()
            }
        }
        .font(Perch.text(12))
        .lineLimit(1)
        .fixedSize()
        .contentTransition(.opacity)
        .animation(Perch.fade, value: entry.delivery)
    }
}

// MARK: - Canvases

#if DEBUG
/// The transcript at its window's size, over a desktop-like gray, the way
/// it stands under the console.
private func card(_ controller: RelayController) -> some View {
    PerchTranscript(controller: controller)
        .frame(width: PerchConsoleView.promptBoxWidth(consoleWidth: Perch.widgetWidth),
               height: PerchTranscript.height)
        .padding(24)
        .background(Color(white: 0.75))
}

/// A run with the given replies in hand, and a note sent with the third
/// handoff when there are that many.
private func playedController(replies: Int, note: Bool = true,
                              summarize: (@Sendable (String) async -> String?)? = nil) -> RelayController {
    let engine = PerchPreviewEngine(turn: replies + 1)
    let controller = connectedController(engine)
    if let summarize { controller.summarizeReply = summarize }
    controller.start()
    let text = "Push on the pricing question before you wrap up."
    for turn in stride(from: 1, through: replies, by: 1) {
        engine.events.post(.reply(side: turn % 2 == 1 ? .chatgpt : .claude, text: PerchPreviewEngine.reply(turn: turn)))
        if note, turn == 3 {
            engine.events.post(.steeringCommitted(note: text, recipient: .claude, turn: 3))
            engine.events.post(.steering(SteeringDelivery(leg: .note, note: text, recipient: .claude, turn: 3,
                                                          outcome: .delivered)))
        }
    }
    return controller
}

#Preview("Transcript · waiting for the first reply") {
    card(playedController(replies: 0))
}

#Preview("Transcript · first reply") {
    // The opening in italics, then the model's sentence a beat later.
    card(playedController(replies: 1))
}

#Preview("Transcript · running") {
    // Seven replies and a note: more lines than the window shows,
    // scrolled to the newest.
    card(playedController(replies: 7))
}

#Preview("Transcript · model unavailable") {
    // No sentence comes, so each line keeps the reply's opening.
    card(playedController(replies: 4, summarize: { _ in nil }))
}
#endif

// The run's log, in the prompt box while the agents work: each reply as a
// line beside the mark of the app that wrote it, summed up by the
// on-device model (ReplySummarizer), and each note the human sent beside
// a person, in the order the conversation took them in. A reply's own
// words stand in italics, on one line, until the model's sentence
// replaces them. The newest line sits at the bottom, level with the run's
// actions, and may take a second line; the ones before it keep one line
// each and fade out toward the top of the box. It is a glance at where the conversation has been, not
// a transcript to read back: it does not scroll, and an older line's full
// text is its tooltip. It shows only while the run goes with the field
// closed: the note editor takes the box while the run is paused, and the
// ending after.

import SwiftUI

struct PerchTranscript: View {
    let controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A row of the log: an entry, or the note queued for the next
    /// handoff, which stays under every reply until it sets off with one.
    private enum Row: Identifiable, Equatable {
        case entry(TranscriptEntry)
        case queued(String)

        var id: String {
            switch self {
            case .entry(let entry): "entry-\(entry.id)"
            case .queued: "queued"
            }
        }
    }

    private var rows: [Row] {
        var rows = controller.transcript.map(Row.entry)
        if let queued = controller.queuedSteering { rows.append(.queued(queued)) }
        return rows
    }

    var body: some View {
        let rows = self.rows
        // The box's space, exactly: the rows stand on its bottom edge at
        // their own heights, and what does not fit goes off the top, under
        // the fade, as the log moves up. (A flexible frame would grow to
        // the rows instead, and clip nothing.)
        Color.clear
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Perch.s(2)) {
                    ForEach(rows) { row in
                        let newest = row.id == rows.last?.id
                        Group {
                            switch row {
                            case .entry(let entry):
                                PerchTranscriptRow(controller: controller, entry: entry, isNewest: newest)
                            case .queued(let note):
                                PerchTranscriptRow(controller: controller,
                                                   entry: TranscriptEntry(id: -1, author: .human,
                                                                          text: ReplySummarizer.flatten(note)),
                                                   isNewest: newest, isQueued: true)
                            }
                        }
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .clipped()
            .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.32)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? Perch.fade : .easeOut(duration: 0.35), value: rows.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The conversation so far")
    }
}

/// One line of the log: whose it is, what it says, whether it signed off,
/// and for a note, where it stands.
private struct PerchTranscriptRow: View {
    let controller: RelayController
    let entry: TranscriptEntry
    let isNewest: Bool
    var isQueued = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(7)) {
            icon
                .frame(width: Perch.s(12), height: Perch.s(12))
                .accessibilityLabel(author)
                // The mark sits on the first line's text, not above it.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Perch.s(1.5) }
            Text(entry.text)
                .font(Perch.text(11))
                .italic(entry.verbatim)
                .foregroundStyle(ink)
                .lineLimit(isNewest && !entry.verbatim ? 2 : 1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(Perch.fade, value: entry.text)
                .perchShimmer(active: entry.summarizing)
                .help(entry.text)
            if entry.author == .human {
                tag
            } else if entry.signsOff {
                Text("\u{00B7} signs off")
                    .font(Perch.text(11))
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

    /// The newest line reads in the box's ink; the ones before it step back.
    /// A reply's own words, in italics on one line, sit a step lighter than
    /// a sentence on it would — lighter still, under the busy shimmer,
    /// while the model writes that sentence — so the log reads as the
    /// model's account, with the replies quoted only where it has none.
    private var ink: Color {
        if entry.summarizing { return Perch.muted }
        if isQueued { return Perch.secondary }
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
    /// queued for the next handoff with the way to drop it, on its way,
    /// or how its handoff went. Its echo to the other side is the ending's
    /// to tell (PerchReceiptLine).
    @ViewBuilder private var tag: some View {
        let recipient = entry.recipient.map(controller.appName)
        Group {
            if isQueued {
                HStack(spacing: Perch.s(8)) {
                    Text(controller.nextRecipient.map { "Queued for \($0)" } ?? "Queued")
                        .foregroundStyle(Perch.accentText)
                    Button {
                        withAnimation(Perch.fade) { _ = controller.clearSteering() }
                    } label: {
                        Text("Clear")
                            .font(Perch.text(11, .medium))
                            .perchHoverInk(idle: Perch.secondary, active: Perch.ink)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Drop the queued note \u{2014} nothing goes with the next handoff")
                }
            } else {
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
        }
        .font(Perch.text(11))
        .lineLimit(1)
        .fixedSize()
        .contentTransition(.opacity)
        .animation(Perch.fade, value: entry.delivery)
    }
}

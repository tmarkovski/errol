// The steering note's chrome outside the field: the line under the head's
// turn line that says where the note is — being written, queued, sending —
// and then what became of it, and the popover that shows a note whole. The
// field itself (PerchComposer) is closed while the agents work, with Pause
// to steer standing in it and a queued note blurred behind; the press opens
// it. The design is docs/design-proposals/steering/the-note-stays-put.md,
// as revised at its end. See PerchHead for the slot this fills.

import SwiftUI

/// The head's steering line. One line in a slot the head reserves for the
/// whole run, so the composer never moves when a note starts; empty when
/// there is nothing to say. A note in flight outranks the open field, the
/// open field outranks a queued note (opening it takes the note back), and
/// the last note's record shows when none of those is true — so closing the
/// field without a note brings the record back. The line describes the
/// note; whether the run is running, pausing, or held is the turn line's to
/// say, right above, and the two never restate each other.
struct PerchSteeringLine: View {
    let controller: RelayController

    private enum Slot: Equatable {
        case sending, queued, writing, record, empty
    }

    private var slot: Slot {
        if controller.steeringInFlight != nil { return .sending }
        if controller.isSteering { return .writing }
        if controller.steeringQueued { return .queued }
        if controller.lastReceipt != nil { return .record }
        return .empty
    }

    var body: some View {
        ZStack {
            switch slot {
            case .sending:
                live("Sending note to \(controller.steeringInFlight?.recipient ?? "the next side")…")
            case .queued:
                live(queuedText)
            case .writing:
                live(writingText)
            case .record:
                if let receipt = controller.lastReceipt {
                    PerchReceiptLine(controller: controller, receipt: receipt)
                        .transition(.opacity)
                }
            case .empty:
                EmptyView()
            }
        }
        .animation(Perch.fade, value: slot)
    }

    /// A line about a note that is still the run's concern, in the quiet
    /// amber the panel uses for "live".
    private func live(_ text: String) -> some View {
        Text(text)
            .font(Perch.text(11))
            .foregroundColor(Perch.accentText)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentTransition(.opacity)
            .animation(Perch.fade, value: text)
            .transition(.opacity)
    }

    /// The field is open. With nothing in it yet, the line says what the
    /// hold is for; with words, who they are for.
    private var writingText: String {
        guard controller.steeringHasText else { return "Steering · write a note, or continue" }
        if let side = controller.nextRecipient { return "Writing a note for \(side)" }
        return "Writing a note for the next handoff"
    }

    private var queuedText: String {
        if let side = controller.nextRecipient {
            return "Note queued · goes to \(side) with the next handoff"
        }
        return "Note queued · goes with the next handoff"
    }
}

/// What became of the last note, in one muted line under the turn line,
/// until the next note or New session. The tooltip is the quick peek at the
/// note; a click or keyboard activation opens it whole.
struct PerchReceiptLine: View {
    let controller: RelayController
    let receipt: SteeringReceipt
    @State private var showingNote = false

    var body: some View {
        let text = receiptText
        Button {
            showingNote.toggle()
        } label: {
            Text(text)
                .font(Perch.text(11))
                .lineLimit(1)
                .truncationMode(.tail)
                .perchHoverInk(idle: tint, active: Perch.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(receipt.note)
        .accessibilityLabel(text)
        .accessibilityHint("Opens the note")
        .popover(isPresented: $showingNote, arrowEdge: .bottom) {
            PerchNotePopover(title: text, note: receipt.note)
        }
        .contentTransition(.opacity)
        .animation(Perch.fade, value: text)
    }

    private var tint: Color {
        if case .notSent = receipt.outcome { return Perch.red }
        return Perch.muted
    }

    private var receiptText: String {
        let recipient = receipt.recipient ?? "the next side"
        let turn = receipt.turn.map { " with turn \($0)" } ?? ""
        var line: String
        switch receipt.outcome {
        case .sent:
            line = "Note sent to " + recipient + turn
        case .unconfirmed:
            line = "Note delivery to " + recipient + turn + " unconfirmed"
        case .notSent(.tooLong):
            line = "Note not sent · too long to send whole"
        case .notSent(.runEnded):
            line = "Note not sent · the run ended with it queued"
        case .notSent:
            line = "Note not sent · never reached \(recipient)"
        case .neverQueued:
            line = "Note in progress · the run ended before it was sent"
        }
        if let echo = receipt.echo, let recipientName = receipt.recipient,
           receipt.outcome == .sent || receipt.outcome == .unconfirmed {
            let other = controller.otherName(than: recipientName)
            switch echo {
            case .shared(let at): line += " · shared with \(other) at turn \(at)"
            case .unconfirmed: line += " · sharing with \(other) unconfirmed"
            case .notShared: line += " · not shared with \(other)"
            }
        }
        return line
    }
}

/// The note in full, selectable, under the line that summarized it.
struct PerchNotePopover: View {
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            Text(title)
                .font(Perch.text(11, .medium))
                .foregroundColor(Perch.muted)
            ScrollView {
                Text(note)
                    .font(Perch.text(12))
                    .foregroundColor(Perch.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Perch.s(14))
        .frame(width: Perch.s(320))
        .frame(maxHeight: Perch.s(280))
        .background(Perch.paper)
    }
}

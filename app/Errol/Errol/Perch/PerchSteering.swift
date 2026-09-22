// The steering note's feedback lines on the console. The native editor
// and the run's actions live in PerchConsole.swift.

import SwiftUI

/// The closed field's line about the note during a run. Ending outranks
/// everything, the note in flight outranks a queued one, the queued note
/// outranks the record (opening the field takes the note back), and the
/// last note's record shows when none of those is true — so closing the
/// field without a note brings the record back. The line describes the
/// note; whether the run is running, pausing, or held is the turn line's
/// to say, and what the open field's keys do is the line under the box
/// (RelayController.steeringHint), so the two never restate each other.
struct PerchRunLine: View {
    let controller: RelayController

    private enum Slot: Equatable {
        case ending, sending, queued, record, empty
    }

    private var slot: Slot {
        if controller.stopRequested { return .ending }
        if controller.steeringInFlight != nil { return .sending }
        if controller.steeringQueued { return .queued }
        if controller.lastReceipt != nil { return .record }
        return .empty
    }

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            switch slot {
            case .ending:
                live("Ending the run at the next safe point…")
            case .sending:
                live("Sending note to \(controller.steeringInFlight?.recipient ?? "the next side")…")
            case .queued:
                live(queuedText)
                clearNote
            case .record:
                if let receipt = controller.lastReceipt {
                    PerchReceiptLine(controller: controller, receipt: receipt)
                        .transition(.opacity)
                }
            case .empty:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Perch.fade, value: slot)
    }

    /// A line about a note that is still the run's concern, in the quiet
    /// accent the panel uses for "live".
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

    private var queuedText: String {
        if let side = controller.nextRecipient {
            return "Note queued · goes to \(side) with the next handoff"
        }
        return "Note queued · goes with the next handoff"
    }

    /// While a note is queued, the one explicit way to drop it without
    /// opening the field. Kept whole: the line beside it truncates first.
    private var clearNote: some View {
        Button {
            withAnimation(Perch.fade) { _ = controller.clearSteering() }
        } label: {
            Text("Clear note")
                .font(Perch.text(11, .medium))
                .perchHoverInk(idle: Perch.secondary, active: Perch.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Drop the queued note — nothing goes with the next handoff")
        .transition(.opacity)
    }
}

/// What became of the last note, in one muted line, until the next note or
/// New session. The tooltip is the quick peek at the note; a click or
/// keyboard activation opens it whole.
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
    }
}

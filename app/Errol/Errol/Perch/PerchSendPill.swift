// The console's Send with who goes first inside it: "Send to" and one
// app's mark, in one accent pill. The other app's mark stands bare just
// outside, to the right; a click on it swaps the two marks, the outside
// one sliding into the pill and the pill's out beside it, so the pill
// always reads where the topic goes and the swap itself shows the change.
// The choice stays open while sending is blocked — the topic can be
// missing and the order still settled — so the outside mark is its own
// button, and only the pill dims.
//
// The pill is drawn by hand: a button style makes one button, and this is
// a button and a choice in one row. It has the prompt box's kind of corner
// (Perch.controlCorner) and wears what the console's prominent capsule
// wears — the accent and its ink — giving the accent up for the well while
// sending is blocked (PerchCapsuleButton); the outside mark wears
// nothing but a tint under the pointer. The marks are drawn once, over
// the row, and matched to the socket each belongs in, so a swap is one
// animated move each way.

import SwiftUI

struct PerchSendPill: View {
    /// A side as the pill shows it: its mark is the app's own flat one
    /// (AppIcons.mark), its initial where the app keeps none.
    struct Side: Identifiable {
        let speaker: Speaker
        let name: String
        let bundleID: String
        var id: Speaker { speaker }
    }

    /// ChatGPT then Claude, as the participants stand.
    let sides: [Side]
    @Binding var first: Speaker
    /// Why sending is unavailable now, or nil when it can go.
    let blocker: String?
    let send: () -> Void
    @Namespace private var sockets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height = Perch.s(29)
    private static let inset = Perch.s(3)
    private static let socketWidth = Perch.s(26)
    private static let shape = RoundedRectangle(cornerRadius: Perch.controlCorner)

    /// Where a mark sits: in the pill, or beside it.
    private enum Socket: Hashable {
        case pill, beside
    }

    /// The accent stands while Send can go.
    private var tinted: Bool { blocker == nil }
    /// The ink on the pill: on the accent, or on the well.
    private var pillInk: Color { tinted ? Perch.onAccent : Perch.ink }
    private var firstSide: Side? { sides.first { $0.speaker == first } }
    private var otherSide: Side? { sides.first { $0.speaker != first } }
    private var firstName: String { firstSide?.name ?? "" }
    private var otherName: String { otherSide?.name ?? "" }

    var body: some View {
        HStack(spacing: Perch.s(4)) {
            pill
            beside
        }
        .overlay { marks }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    /// "Send to" and the socket the first side's mark sits in, one button.
    private var pill: some View {
        Button(action: send) {
            HStack(spacing: 0) {
                Text("Send to")
                    .font(Perch.text(12, .medium))
                    .foregroundStyle(tinted ? pillInk : Perch.secondary)
                    .padding(.leading, Perch.s(14))
                    .padding(.trailing, Perch.s(2))
                socket(.pill)
                    .padding(.trailing, Perch.s(5))
            }
            .frame(height: Self.height)
            .background(Self.shape.fill(tinted ? Perch.accent : Perch.well))
            .overlay(Self.shape.stroke(tinted ? Color.clear : Perch.chipEdge, lineWidth: 1))
            .perchHover(Self.shape, tint: tinted ? .white : Perch.ink, opacity: tinted ? 0.12 : 0.06)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .disabled(blocker != nil)
        .keyboardShortcut(.defaultAction)
        .animation(Perch.fade, value: tinted)
        .help(blocker ?? "Send the topic to \(firstName) and start relaying")
        .accessibilityLabel("Send to \(firstName)")
    }

    /// The other side's mark, bare beside the pill: a click puts that side
    /// first, and the marks trade places. Only the pointer marks it as a
    /// button, with a tint under it.
    private var beside: some View {
        Button {
            guard let other = otherSide else { return }
            first = other.speaker
        } label: {
            socket(.beside)
                .padding(Self.inset)
                .frame(height: Self.height)
                .perchHover(Self.shape)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .help("\(otherName) goes first instead: the topic is sent to it")
        .accessibilityLabel("Send to \(otherName) instead")
    }

    /// A socket: the space a mark lands in, and the source of its frame.
    /// Nothing is drawn; the mark over it is all there is to see.
    private func socket(_ socket: Socket) -> some View {
        Color.clear
            .frame(width: Self.socketWidth, height: Self.height - 2 * Self.inset)
            .matchedGeometryEffect(id: socket, in: sockets)
    }

    /// Both marks, each taking the frame of the socket it belongs in. They
    /// are drawn over the buttons and let clicks through to them, so a
    /// swap is the marks moving and nothing else.
    private var marks: some View {
        ZStack {
            ForEach(sides) { side in
                let inPill = side.speaker == first
                mark(side)
                    .foregroundStyle(inPill ? pillInk : Perch.ink)
                    .frame(width: Self.socketWidth, height: Self.height - 2 * Self.inset)
                    .matchedGeometryEffect(id: inPill ? Socket.pill : .beside, in: sockets, isSource: false)
            }
        }
        .animation(reduceMotion ? nil : Perch.spring, value: first)
        .animation(Perch.fade, value: tinted)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func mark(_ side: Side) -> some View {
        if let image = AppIcons.mark(forBundleID: side.bundleID) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: Perch.s(14), height: Perch.s(14))
        } else {
            Text(String(side.name.prefix(1)))
                .font(Perch.text(12, .semibold))
        }
    }
}

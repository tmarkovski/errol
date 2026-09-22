// The console's Send with who goes first inside it: "Send to" is the
// action, the two apps' marks beside it the choice, in one accent pill.
// Choosing is a click on a mark and the thumb slides to it; the status
// line above names the result. The choice stays open while sending is
// blocked — the topic can be missing and the order still settled — so the
// marks are their own buttons, and only "Send to" dims.
//
// The pill is drawn by hand where the other capsules use the system's
// glass button styles: a style makes one button, and this is a button and
// a segmented choice in one shape. It borrows what those styles do — the
// accent tint and its ink, given up while sending is blocked and while
// the console is not key (PerchCapsuleButton) — and, like the arrangement
// capsule, keeps the glass as a background layer so a drag inside it does
// not move the window (PanelWindowSurface).

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
    @Namespace private var thumb
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height = Perch.s(29)
    private static let inset = Perch.s(3)

    /// The accent stands while Send can go and the console is key.
    private var tinted: Bool { blocker == nil && appearsActive }
    /// The marks' ink: on the accent, or on bare glass.
    private var ink: Color { tinted ? Perch.onAccent : Perch.ink }
    private var firstName: String { sides.first { $0.speaker == first }?.name ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: send) {
                Text("Send to")
                    .font(Perch.text(12, .medium))
                    .foregroundStyle(blocker == nil ? ink : Perch.secondary)
                    .padding(.leading, Perch.s(14))
                    .padding(.trailing, Perch.s(8))
                    .frame(height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(blocker != nil)
            .keyboardShortcut(.defaultAction)
            .help(blocker ?? "Send the topic to \(firstName) and start relaying")
            .accessibilityLabel("Send to \(firstName)")
            marks
        }
        .background(Color.clear.glassEffect(tinted ? .regular.tint(Perch.accent) : .regular, in: Capsule()))
        .animation(Perch.fade, value: tinted)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    /// The choice, as the arrangement capsule draws its own: a thumb on the
    /// chosen mark, a hairline between the others that hides beside it.
    private var marks: some View {
        HStack(spacing: 0) {
            ForEach(Array(sides.enumerated()), id: \.element.id) { index, side in
                if index > 0 {
                    Rectangle().fill(ink.opacity(tinted ? 0.35 : 0.2))
                        .frame(width: 1, height: Perch.s(14))
                        .opacity(first == side.speaker || first == sides[index - 1].speaker ? 0 : 1)
                        .accessibilityHidden(true)
                }
                Button { first = side.speaker } label: {
                    mark(side)
                        .foregroundStyle(ink)
                        .frame(width: Perch.s(34), height: Self.height - 2 * Self.inset)
                        .background {
                            if first == side.speaker {
                                Capsule().fill(ink.opacity(tinted ? 0.28 : 0.11))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .perchHover(Capsule(), tint: ink, opacity: tinted ? 0.12 : 0.06)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(side.name) goes first: the topic is sent to it")
                .accessibilityLabel("\(side.name) goes first")
                .accessibilityAddTraits(first == side.speaker ? .isSelected : [])
            }
        }
        .padding(.trailing, Self.inset)
        .animation(reduceMotion ? nil : Perch.spring, value: first)
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

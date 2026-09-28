// App identity at the ends; destination details use the wider line below the box
// (PerchDestinations.swift), and what both say is read in ParticipantPresentation.swift.
//
// Each end is the app's icon with a state badge straddling its lower trailing
// corner, and the app's name under it. A click on the icon focuses the app,
// its connected window in front, or opens it when it is closed. Resting the
// pointer on the icon brings up its tip (PerchParticipantTip): what a click
// does, then the window's mode, model, effort, and state.
import SwiftUI

struct PerchParticipant: View {
    @Bindable var controller: RelayController
    let speaker: Speaker
    @State private var hovering = false
    /// The tip, once the pointer has rested on the icon a moment.
    @State private var tipShown = false
    @State private var tipDelay: Task<Void, Never>?
    /// A click puts the tip away until the pointer leaves the icon.
    @State private var tipSpent = false

    /// How long the pointer rests on the icon before its tip shows.
    static let tipWait = Duration.milliseconds(450)

    var body: some View {
        let presentation = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(spacing: Perch.s(6)) {
            Button { click(presentation.click) } label: {
                PerchAvatar(bundleID: presentation.bundleID,
                            initial: String(presentation.name.prefix(1)), feather: presentation.feather)
                    .opacity(presentation.state == .waiting ? 0.8 : 1)
                    .animation(Perch.fade, value: presentation.state)
                    // The icon answers the pointer the way a Dock icon does:
                    // it darkens a little. The badge keeps its color.
                    .brightness(hovering ? -0.06 : 0)
                    // A little shadow lifts the icon off the shell, as the
                    // prompt box's lifts the box. The badge is cut out of
                    // the artwork, so it takes none of its own.
                    .shadow(color: Perch.shadow, radius: Perch.s(2), y: Perch.s(1))
                    .overlay(alignment: .bottomTrailing) {
                        ParticipantBadge(state: presentation.state)
                            .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] + ParticipantBadge.cornerInset }
                            .alignmentGuide(.bottom) { $0[VerticalAlignment.center] + ParticipantBadge.cornerInset }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: hover)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onKeyPress(.return) {
                click(presentation.click)
                return .handled
            }
            .accessibilityLabel(presentation.name)
            .accessibilityValue(presentation.spokenFacts)
            .accessibilityHint(presentation.click.hint(name: presentation.name))
            .background {
                if let source = controller.iconTransferSources[speaker] {
                    TransferAnchorProbe(source: source).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background {
                PerchTipAnchor(isPresented: $tipShown) {
                    PerchParticipantTip(controller: controller, speaker: speaker)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Text(presentation.name).font(Perch.text(12, .medium)).foregroundStyle(Perch.ink)
                .lineLimit(1).frame(height: Perch.s(17))
        }
        .frame(width: Perch.participantWidth)
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        tipDelay?.cancel()
        guard inside else {
            tipShown = false
            tipSpent = false
            return
        }
        guard !tipSpent else { return }
        tipDelay = Task { @MainActor in
            try? await Task.sleep(for: Self.tipWait)
            if !Task.isCancelled { tipShown = true }
        }
    }

    private func click(_ click: ParticipantPresentation.Click) {
        tipDelay?.cancel()
        tipShown = false
        tipSpent = true
        switch click {
        case .focus: controller.showWindow(speaker, returningKeyboard: false)
        case .open: controller.setup.launch(speaker)
        case .unavailable: break
        }
    }
}

/// A state as a badge: the state's mark on its color, ringed in the
/// window's shell where it sits over an icon, so it reads as cut out of the
/// artwork. A new state replaces the mark in place.
struct ParticipantBadge: View {
    let state: ParticipantState
    var size = Perch.s(12)
    var ringed = true

    /// How far in from the icon frame's corner the badge's center sits: on
    /// the squircle's rounded corner, so the badge straddles the icon's edge
    /// instead of sitting inside the artwork.
    static let cornerInset = Perch.s(3.5)

    var body: some View {
        Image(systemName: state.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(state.mark, state.color)
            .font(.system(size: size, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .background {
                if ringed { Circle().fill(Perch.shell).padding(-Perch.s(0.5)) }
            }
            .animation(Perch.fade, value: state)
            .accessibilityLabel(state.title)
    }
}

/// A side's tip, from its icon: what a click does, then what the side's
/// window is set to, one fact a line, the labels in a column of their own.
/// PerchTip draws it white on black.
struct PerchParticipantTip: View {
    let controller: RelayController
    let speaker: Speaker

    var body: some View {
        let info = ParticipantPresentation(controller: controller, speaker: speaker)
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            if let line = info.click.line {
                let actionable = info.click == .focus || info.click == .open
                Text(line).font(Perch.text(12, .semibold))
                    .foregroundStyle(.white.opacity(actionable ? 1 : 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Perch.s(12), verticalSpacing: Perch.s(4)) {
                ForEach(info.facts) { fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(.white.opacity(0.55)).fixedSize()
                        value(fact)
                    }
                }
            }
            .font(Perch.text(11.5))
        }
    }

    private func value(_ fact: ParticipantFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Perch.s(4)) {
            if let badge = fact.badge {
                ParticipantBadge(state: badge, size: Perch.s(10), ringed: false)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Perch.s(3.5) }
            }
            Text(fact.value).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .lineLimit(3)
    }
}

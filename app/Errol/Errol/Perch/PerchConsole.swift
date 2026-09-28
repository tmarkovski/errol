// The fixed console: its columns, and the top row of session options and the app menu.
// The prompt box lives in PerchPromptBox.swift, the destinations in PerchDestinations.swift.

import AppKit
import SwiftUI

struct PerchConsoleView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth

    var body: some View {
        let focusAsk = PerchFocusAlert.ask(for: controller)
        HStack(spacing: PerchMetrics.columnGap) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                PerchTopicLine(controller: controller)
                PerchPromptBox(controller: controller)
                PerchDestinations(controller: controller)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)
            PerchParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, PerchMetrics.endInset)
        .padding(.vertical, Perch.s(8))
        // Under the alert, the console is only something to see through,
        // softened so its lines do not compete with the ask.
        .blur(radius: focusAsk != nil ? Perch.s(6) : 0)
        .accessibilityHidden(focusAsk != nil)
        .overlay {
            if let focusAsk {
                PerchFocusAlert(controller: controller, ask: focusAsk)
                    .transition(.opacity)
            }
        }
        .animation(PerchFocusAlert.fade, value: focusAsk)
        .frame(width: width, height: Perch.widgetHeight)
        .tint(Perch.accent)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .clipShape(Capsule())
    }
}

// MARK: - Session options and the app menu

/// Before a run, the run's settings as chips that show their values; during
/// and after one, the topic. The ··· app menu stands at the trailing end in
/// every stage, with the update beside it while one is on offer and no run
/// is live. A chip's width follows its value, so choosing another one
/// springs the chip, and the chips after it, to the new width. Who starts is
/// a choice of two, so its chip swaps with a click instead of opening a
/// menu. With a turn limit, a stepper stands beside the ending chip and sets
/// the count.
struct PerchTopicLine: View {
    @Bindable var controller: RelayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The turn limit's range: one reply at the least, and two digits at the
    /// most. A run that should go on longer ends when you stop it.
    static let turnRange = 1...99

    var body: some View {
        HStack(spacing: Perch.s(6)) {
            if controller.stage == .compose {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Perch.s(6)) { starterSwap; endingControl; windowsMenu }.fixedSize()
                    HStack(spacing: Perch.s(6)) { endingControl; runOptionsMenu }.fixedSize()
                }
            } else {
                let topic = controller.topicSummary ?? controller.runPrompt ?? "Conversation"
                Text(topic).font(Perch.text(12, .medium))
                    .foregroundStyle(Perch.ink).lineLimit(1).help(topic)
                    .padding(.leading, PerchChip.inset)
            }
            Spacer(minLength: 0)
            PerchUpdateButton(hidden: controller.stage == .running)
            PerchAppMenuButton(controller: controller)
        }
        .animation(reduceMotion ? nil : Perch.spring, value: [starterTitle, endingTitle, windowsTitle])
        .padding(.leading, PerchMetrics.promptTextInset - PerchChip.inset)
        .padding(.trailing, Perch.s(7) - PerchChip.inset)
        .frame(height: Perch.s(22))
    }

    private var starterTitle: String { "\(controller.appName(controller.firstSpeaker)) starts" }

    /// The side a click on the starter hands the first turn to.
    private var otherStarter: Speaker { controller.firstSpeaker.other }

    private var endingTitle: String {
        switch controller.ending {
        case .bothAgree: "Ends when both agree"
        case .turnLimit: controller.turns == 1 ? "Ends after 1 turn" : "Ends after \(controller.turns) turns"
        case .whenStopped: "Ends when you stop it"
        }
    }

    private var endingHelp: String {
        switch controller.ending {
        case .bothAgree: "Ends when both assistants sign off"
        case .turnLimit: "A maximum: if both assistants sign off sooner, the run ends then"
        case .whenStopped: "Keeps going until you press Stop; the assistants are told there is no sign-off"
        }
    }

    private var windowsTitle: String { controller.setup.state.layout.consoleTitle }

    private var starterSwap: some View {
        PerchChipSwap(title: controller.appName(controller.firstSpeaker), suffix: " starts",
                      turned: controller.firstSpeaker == .claude) {
            controller.firstSpeaker = otherStarter
        }
        .help("Let \(controller.appName(otherStarter)) start instead")
        .accessibilityLabel("Who starts")
        .accessibilityValue(controller.appName(controller.firstSpeaker))
        .accessibilityHint("Switches to \(controller.appName(otherStarter))")
    }

    /// The ending chip, and the turn limit's stepper beside it while that is
    /// the ending. Stepping rolls the chip's count.
    private var endingControl: some View {
        HStack(spacing: Perch.s(2)) {
            PerchChipMenu(title: endingTitle,
                          value: controller.ending == .turnLimit ? Double(controller.turns) : nil) { endingItems }
                .help(endingHelp)
            if controller.ending == .turnLimit {
                PerchStepper(value: $controller.turns, range: Self.turnRange, label: "Turn limit",
                             unit: { $0 == 1 ? "1 turn" : "\($0) turns" },
                             decrementHelp: "Fewer turns", incrementHelp: "More turns")
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
    }

    private var windowsMenu: some View {
        PerchChipMenu(title: windowsTitle) { windowsItems }
            .help("Choosing an arrangement moves the connected windows immediately")
            .disabled(controller.isShowingWindow)
    }

    /// The narrow console's fallback: who starts as one command that swaps
    /// it, like the chip, and the arrangement as a submenu titled with its
    /// value. The ending stays out on the row, where its stepper can stand
    /// beside it.
    private var runOptionsMenu: some View {
        PerchChipMenu(title: "Run options") {
            Button { controller.firstSpeaker = otherStarter } label: {
                Label("Let \(controller.appName(otherStarter)) start", systemImage: PerchChipSwap.symbol)
            }
            Menu(windowsTitle) { windowsItems }
                .disabled(controller.isShowingWindow)
        }
        .help("\(starterTitle) \u{00B7} \(windowsTitle)")
    }

    // Toggles, so the menu checks the value in force in its own column.
    // Choosing the checked one again changes nothing.

    /// The three endings. The turn limit's count is set with the stepper
    /// that appears beside the chip, not here.
    @ViewBuilder private var endingItems: some View {
        ForEach(RunEnding.allCases, id: \.self) { ending in
            Toggle(ending.menuTitle, isOn: Binding(
                get: { controller.ending == ending },
                set: { if $0 { controller.ending = ending } }))
        }
    }

    @ViewBuilder private var windowsItems: some View {
        ForEach(LayoutChoice.allCases, id: \.self) { layout in
            Toggle(isOn: Binding(
                get: { controller.setup.state.layout == layout },
                set: { if $0 { controller.setup.choose(layout) } })) {
                Label(layout.title, systemImage: layout.symbol)
            }
        }
        Divider()
        Button("Restore window positions") { controller.setup.restoreLayout() }
            .disabled(!controller.setup.canRestoreLayout)
    }
}

/// The ··· at the top row's trailing end: the app menu the status item
/// also shows (MenuBarController.makeAppMenu), popped under the chip.
struct PerchAppMenuButton: View {
    let controller: RelayController
    @State private var anchor = PerchMenuAnchor.Reference()

    var body: some View {
        Button {
            guard let view = anchor.view, let menu = controller.appMenuProvider?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + Perch.s(4)), in: view)
        } label: {
            // Drawn rather than the ellipsis symbol: under the console's
            // capsule clip, the offscreen renders drew that symbol in white
            // in every rendering mode, while plain shapes keep their ink.
            HStack(spacing: Perch.s(2.6)) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: Perch.s(3.3), height: Perch.s(3.3))
                }
            }
            .foregroundStyle(Perch.secondary)
            .perchChip()
        }
        .buttonStyle(.plain)
        .background(PerchMenuAnchor(reference: anchor).allowsHitTesting(false).accessibilityHidden(true))
        .help("App menu")
        .accessibilityLabel("App menu")
    }
}

/// Where an AppKit menu pops up from a SwiftUI control: a flipped view in
/// the control's background, so y grows downward from its top edge.
struct PerchMenuAnchor: NSViewRepresentable {
    @MainActor
    final class Reference {
        weak var view: NSView?
    }

    private final class AnchorView: NSView {
        override var isFlipped: Bool { true }
    }

    let reference: Reference

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        reference.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { reference.view = view }
}

// MARK: - The ending

extension RunEnding {
    /// Each ending as the menu lists it, completing the chip's "Ends …".
    var menuTitle: String {
        switch self {
        case .bothAgree: "When both agree"
        case .turnLimit: "After a set number of turns"
        case .whenStopped: "When you stop it"
        }
    }
}

// MARK: - The window arrangement

extension LayoutChoice {
    var consoleTitle: String {
        switch self {
        case .sideBySide: "Windows side by side"
        case .stacked: "Windows stacked"
        case .fullScreen: "Windows fill screen"
        case .keepPositions: "Windows: keep positions"
        }
    }

    var symbol: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        case .fullScreen: return "rectangle"
        case .keepPositions: return "macwindow.on.rectangle"
        }
    }
}

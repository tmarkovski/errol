// The fixed console: session options, editor or status panel, and persistent destinations.

import AppKit
import SwiftUI

struct PerchConsoleView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    /// The columns' inset from the capsule's ends, and the gap between a
    /// column and the middle.
    static let endInset = Perch.s(28)
    static let columnGap = Perch.s(14)

    /// The prompt box's width in a console of the given width: what the
    /// two columns leave between them. The transcript under the console
    /// takes the same width, to stand as the box's continuation.
    static func promptBoxWidth(consoleWidth: CGFloat) -> CGFloat {
        consoleWidth - 2 * (endInset + Perch.participantWidth + columnGap)
    }

    var body: some View {
        let focusSide = PerchFocusAlert.side(for: controller)
        HStack(spacing: Self.columnGap) {
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
        .padding(.horizontal, Self.endInset)
        .padding(.vertical, Perch.s(8))
        // Under the alert, the console is only something to see through,
        // softened so its lines do not compete with the ask.
        .blur(radius: focusSide != nil ? Perch.s(6) : 0)
        .accessibilityHidden(focusSide != nil)
        .overlay {
            if let focusSide {
                PerchFocusAlert(controller: controller, side: focusSide)
                    .transition(.opacity)
            }
        }
        .animation(PerchFocusAlert.fade, value: focusSide)
        .frame(width: width, height: Perch.widgetHeight)
        .tint(Perch.accent)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .clipShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onCardResize?($0) }
    }
}

// MARK: - Session options and the app menu

/// Before a run, the run's settings as chips that show their values; during
/// and after one, the topic. The ··· app menu stands at the trailing end in
/// every stage. A chip's width follows its value, so choosing another one
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
            PerchAppMenuButton(controller: controller)
        }
        .animation(reduceMotion ? nil : Perch.spring, value: [starterTitle, endingTitle, windowsTitle])
        .padding(.leading, PerchPromptBox.textInset - PerchChip.inset)
        .padding(.trailing, Perch.s(7) - PerchChip.inset)
        .frame(height: Perch.s(22))
    }

    private var starterTitle: String { "\(controller.appName(controller.firstSpeaker)) starts" }

    /// The side a click on the starter hands the first turn to.
    private var otherStarter: Speaker { controller.firstSpeaker == .chatgpt ? .claude : .chatgpt }

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
        PerchChipSwap(title: starterTitle, turned: controller.firstSpeaker == .claude) {
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
            controller.presentedParticipant = nil
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

extension RelayController {
    /// Keyboard hints beside Resume or Send note & continue.
    var steeringHint: String {
        let side = nextRecipient
        if steeringHasText {
            return side.map { "Return sends it to \($0) \u{00B7} Esc clears it" }
                ?? "Return sends it with the next handoff \u{00B7} Esc clears it"
        }
        return side.map { "Write a note for \($0) \u{00B7} Return or Esc resumes without one" }
            ?? "Write a note \u{00B7} Return or Esc resumes without one"
    }

    /// The status panel headline follows the actual relay state.
    var runHeadline: String {
        if stopRequested { return "Ending at the next safe point\u{2026}" }
        if let block { return block.headline(names: names) }
        if isSteeringPending { return "Pausing after the current handoff\u{2026}" }
        if isHolding { return "Paused \u{00B7} Nothing is being copied or sent" }
        switch (chatgptConversation, claudeConversation) {
        case (.chatting, _): return "\(names.chatgpt) is replying\u{2026}"
        case (_, .chatting): return "\(names.claude) is replying\u{2026}"
        case (.replied, _): return "Sending \(names.chatgpt)'s reply to \(names.claude)"
        case (_, .replied): return "Sending \(names.claude)'s reply to \(names.chatgpt)"
        default:
            return currentTurn == 0
                ? "Sending the topic to \(appName(firstSpeaker))\u{2026}"
                : "Relaying the reply\u{2026}"
        }
    }
}

/// The run's turn and clock, at the status line's trailing end.
struct PerchRunMetadata: View {
    let controller: RelayController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let turn = controller.ending == .turnLimit ? "Turn \(controller.currentTurn) of \(controller.turns)"
                : "Turn \(controller.currentTurn)"
            // Nothing else says a run of this kind won't end by itself.
            let until = controller.ending == .whenStopped ? " \u{00B7} until you stop it" : ""
            Text("\(turn) · \(runClock(controller.elapsedRunDuration(at: context.date)))\(until)")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - The prompt box

/// Only composing and a granted pause mount a text editor. The remaining
/// stages show accessible status text with stable actions.
struct PerchPromptBox: View {
    @Bindable var controller: RelayController

    static let textInset = Perch.s(12)
    static let corner = Perch.s(16)
    /// The box's inset above its text and below its toolbar.
    static let verticalInset = Perch.s(6)

    private var editing: Bool { controller.stage == .compose || controller.consoleAccess.pauseGranted }

    var body: some View {
        Group {
            if editing {
                VStack(alignment: .leading, spacing: Perch.s(4)) {
                    Group {
                        if controller.stage == .compose { openingEditor } else { steering }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Self.textInset)
                    // The hint starts where the text above it does, and its
                    // bottom lines up with the buttons'.
                    HStack(alignment: .bottom, spacing: Perch.s(8)) {
                        Text(editorHint)
                            .font(Perch.text(11))
                            .foregroundStyle(controller.failedStart == nil ? Perch.secondary : Perch.red)
                            .lineLimit(2).help(editorHint)
                        Spacer(minLength: 0)
                        PerchConsoleActions(controller: controller)
                    }
                    .padding(.leading, Self.textInset)
                    .padding(.trailing, Perch.s(7))
                }
            } else {
                statusPanel
            }
        }
        .padding(.vertical, Self.verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A very soft shadow all around lifts the box off the shell.
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(editing ? Perch.paper : Perch.well)
            .shadow(color: Perch.shadow, radius: Perch.s(7), y: Perch.s(1.5)))
        .overlay(RoundedRectangle(cornerRadius: Self.corner)
            .stroke(controller.consoleAccess.pauseGranted ? Perch.accent : Perch.chipEdge,
                    lineWidth: controller.consoleAccess.pauseGranted ? 1.5 : 1))
        .background {
            PromptTransferProbe(source: controller.promptTransferSource)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var editorHint: String {
        if controller.consoleAccess.pauseGranted { return controller.steeringHint }
        return controller.failedStart ?? controller.setup.problem ?? controller.setup.state.layoutProblem
            ?? controller.sendBlocker ?? ""
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: Perch.s(9)) {
            statusIcon.frame(width: Perch.s(24), height: Perch.s(24))
            VStack(alignment: .leading, spacing: Perch.s(3)) {
                Text(headline).font(Perch.text(13, .semibold))
                    .foregroundStyle(needsAttention ? Perch.red : Perch.ink)
                    .lineLimit(2).help(headline)
                if controller.stage == .finished {
                    let detail = controller.lastReport?.detail(names: controller.names,
                                                               timeout: config.timeout) ?? ""
                    if !detail.isEmpty {
                        Text(detail).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                            .lineLimit(3).help(detail)
                    }
                } else if let block = controller.block, !controller.stopRequested {
                    let recovery = block.recovery(names: controller.names)
                    Text(recovery).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                        .lineLimit(3).help(recovery)
                } else if controller.steeringQueued {
                    PerchRunLine(controller: controller)
                    Text(controller.steeringText).font(Perch.text(11))
                        .foregroundStyle(Perch.secondary).lineLimit(1).help(controller.steeringText)
                } else if controller.isSteeringPending {
                    Text("Finishing the current copy or delivery before you can write.")
                        .font(Perch.text(11)).foregroundStyle(Perch.secondary).lineLimit(2)
                }
                if controller.stage == .running { PerchRunMetadata(controller: controller) }
                // While a stop is under way the headline says so, and the
                // note's line waits for the run's end: a note the stop left
                // unsent shows then.
                if !controller.steeringQueued && !(controller.stopRequested && controller.stage == .running) {
                    if controller.steeringInFlight != nil {
                        PerchRunLine(controller: controller)
                    } else if let receipt = controller.lastReceipt,
                              controller.stage != .finished || receipt.outcome != .sent {
                        // After the run, a note that went is on its line in
                        // the conversation summary. One that didn't stays
                        // here: a queued note the run ended with, or words
                        // never sent, is on no line there.
                        PerchReceiptLine(controller: controller, receipt: receipt)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PerchConsoleActions(controller: controller)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, Self.textInset)
    }

    private var headline: String {
        controller.stage == .finished
            ? controller.lastReport?.headline(names: controller.names) ?? "Run ended"
            : controller.runHeadline
    }

    private var needsAttention: Bool {
        controller.stage == .finished ? controller.lastReport?.outcome.needsAttention == true
            : controller.block != nil && !controller.stopRequested
    }

    @ViewBuilder private var statusIcon: some View {
        if controller.stage == .finished {
            Image(systemName: controller.lastReport?.outcome.symbol ?? "stop.circle")
                .font(Perch.text(20))
                .foregroundStyle(needsAttention ? Perch.red
                    : controller.lastReport?.outcome == .completed ? Perch.accentText : Perch.secondary)
        } else if needsAttention {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Perch.red)
        } else {
            let speaker: Speaker = controller.chatgptConversation == .chatting || controller.chatgptConversation == .replied
                ? .chatgpt : controller.claudeConversation == .notStarted ? controller.firstSpeaker : .claude
            PerchAvatar(bundleID: speaker == .chatgpt ? config.chatgptBundleID : config.claudeBundleID,
                        initial: String(controller.appName(speaker).prefix(1)),
                        feather: speaker == .chatgpt ? Perch.chatgptFeather : Perch.claudeFeather)
                .scaleEffect(0.48).frame(width: Perch.s(24), height: Perch.s(24))
                .accessibilityHidden(true)
        }
    }

    // MARK: Before a run

    /// Return sends only when Send would: a refusal the status line already
    /// explains is not also recorded as a failed start.
    @ViewBuilder private var openingEditor: some View {
        if controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              fitsAvailableHeight: true,
                              takesFocusOnAppear: true)
        } else {
            GrowingTextEditor(text: $controller.topic,
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              fitsAvailableHeight: true,
                              takesFocusOnAppear: true,
                              onSubmit: { if controller.sendBlocker == nil { controller.start() } })
        }
    }

    private var topicPlaceholder: String {
        if let template = controller.selectedTemplate { return template.topicPrompt }
        return "What should they work on together?"
    }

    // MARK: During a run

    /// The note editor. What its keys do is said under the box
    /// (RelayController.steeringHint).
    private var steering: some View {
        GrowingTextEditor(text: Binding(get: { controller.steeringText },
                                           set: { controller.setSteeringText($0) }),
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.steeringText.isEmpty
                                  ? "A note for the next handoff\u{2026}" : nil,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              fitsAvailableHeight: true, takesFocusOnAppear: true,
                              onSubmit: { controller.sendSteering() },
                              onEscape: { _ in controller.escapeSteering() },
                              session: controller.steeringEditor)
    }

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

    var actionHelp: String {
        switch self {
        case .sideBySide: return "Move both windows side by side now"
        case .stacked: return "Move both windows into a stack now"
        case .fullScreen: return "Make both windows fill the screen now, one over the other"
        case .keepPositions: return "Leave both windows where they are"
        }
    }
}

// MARK: - The actions

/// The primary action and run controls stay at the trailing end.
struct PerchConsoleActions: View {
    @Bindable var controller: RelayController

    private var setup: SetupController { controller.setup }

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            switch controller.stage {
            case .compose:
                if closedApps.isEmpty { send } else { open }
            case .running:
                if controller.consoleAccess.pauseGranted { paused } else { running }
            case .finished:
                finished
            }
        }
        .fixedSize()
    }

    private var closedApps: [Speaker] {
        [Speaker.chatgpt, .claude].filter { setup.state[$0].presence == .notRunning }
    }

    /// Apps open only through this explicit action or the participant popover.
    private var open: some View {
        let title = closedApps.count == 2 ? "Open both apps" : "Open \(setup.name(closedApps[0]))"
        return PerchCapsuleButton(title: title, icon: "arrow.up.right") { setup.launchBoth() }
            .help("Open whichever app isn\u{2019}t open yet")
    }

    private var send: some View {
        PerchCapsuleButton(title: "Start relay", icon: "arrow.right") { controller.start() }
            .disabled(controller.sendBlocker != nil)
            .help(controller.sendBlocker ?? "Send the topic to \(controller.appName(controller.firstSpeaker)) and begin relaying")
    }

    /// The status panel names a pending pause; Stop remains available.
    private var running: some View {
        HStack(spacing: Perch.s(8)) {
            PerchRoundButton(title: controller.steeringQueued ? "Edit note" : "Pause to steer",
                             icon: "pause.fill") { controller.beginSteering() }
                .disabled(controller.isSteeringPending || controller.stopRequested)
            PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) { controller.stop() }
                .disabled(controller.stopRequested)
        }
    }

    /// One button continues the run: Resume while the field is empty,
    /// Send note once it has words. Stop stands at the end, where it does
    /// while the run is going.
    private var paused: some View {
        let hasNote = controller.steeringHasText
        return HStack(spacing: Perch.s(8)) {
            PerchCapsuleButton(title: hasNote ? "Send note & continue" : "Resume",
                               icon: hasNote ? "arrow.up" : "play.fill") { controller.sendSteering() }
                .help(hasNote
                      ? (controller.nextRecipient.map { "The note goes to \($0) with the next handoff" }
                         ?? "The note goes with the next handoff")
                      : "Continue without a note")
                .animation(Perch.fade, value: hasNote)
                .disabled(!controller.consoleAccess.canResume)
            PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
        }
    }

    /// One way on. The connections are held, and both are read again before
    /// Send is offered; a conversation changed in the apps meanwhile is
    /// picked up the way any other is.
    private var finished: some View {
        PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") { controller.anotherTopicHere() }
            .keyboardShortcut(.defaultAction)
            .help("Write another topic for these conversations; their context carries on")
    }
}

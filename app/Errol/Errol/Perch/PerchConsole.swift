// The console the app shows: the prompt from the start, with no steps
// before it. The participants stand at the capsule's ends as they always
// have; between them one line of status sits above a prompt box, and the
// box holds the text over a toolbar row — the window arrangement at its
// leading end, the actions at its trailing end. Under the box, at each
// side's end, stand its surface and model as the sweep reads them. Every
// stage shares that frame: the topic editor, then the run with the field
// closed or the steering note open in it, then the ending.
//
// What the four guided steps did is folded into it. The icons open the
// apps, the arrangement applies as it is chosen, each side is connected as
// SetupController.connectIfUnambiguous has it, and the status line names the
// next thing a side needs. The guided capsule (PerchPanelView, PerchSetup)
// and the drag to connect are kept, out of the app's path, for later use.
// The session's options moved to the status item's menu.

import SwiftUI

struct PerchConsoleView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: Perch.s(14)) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                PerchConsoleStatus(controller: controller)
                PerchPromptBox(controller: controller)
                PerchSurfaceLabels(controller: controller)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)
            PerchParticipant(controller: controller, speaker: .claude)
        }
        .padding(.horizontal, Perch.s(28))
        .padding(.vertical, Perch.s(10))
        .frame(width: width, height: Perch.widgetHeight)
        .tint(Perch.accent)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .clipShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onCardResize?($0) }
    }
}

// MARK: - The status line

/// One line above the prompt, whatever the stage: what a side still needs
/// before Send, what the apps are doing during a run, how the run ended.
/// A run's turn and clock stand at its trailing end.
struct PerchConsoleStatus: View {
    let controller: RelayController

    var body: some View {
        let status = self.status
        HStack(spacing: Perch.s(8)) {
            Text(status.text)
                .font(Perch.text(12))
                .foregroundStyle(status.isProblem ? Perch.red : Perch.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(status.text)
                .contentTransition(.opacity)
                .perchShimmer(active: isWorking)
            Spacer(minLength: 0)
            if controller.stage == .running {
                PerchRunMetadata(controller: controller)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        // The line starts where the prompt's text does.
        .padding(.horizontal, PerchPromptBox.textInset)
        .frame(height: Perch.s(17))
        .animation(Perch.fade, value: status)
        .accessibilityElement(children: .combine)
    }

    private var status: SetupNotice {
        switch controller.stage {
        case .setup, .compose:
            // A start the engine refused outranks what the sweeps say: it
            // is the answer to the click just made.
            if let failed = controller.failedStart { return SetupNotice(text: failed, isProblem: true) }
            if let notice = controller.setup.notice { return notice }
            return SetupNotice(text: "Both conversations are connected. "
                               + "\(controller.appName(controller.firstSpeaker)) goes first.", isProblem: false)
        case .running:
            return SetupNotice(text: controller.runHeadline,
                               isProblem: controller.block != nil && !controller.stopRequested)
        case .finished:
            return SetupNotice(text: controller.lastReport?.headline(names: controller.names) ?? "Run ended",
                               isProblem: false)
        }
    }

    /// The apps are at work and nothing is asked of the human.
    private var isWorking: Bool {
        controller.stage == .running && !controller.isSteering && !controller.holdRequested
            && !controller.stopRequested && controller.block == nil
    }
}

// MARK: - The prompt box

/// The box under the status: text over a toolbar row. The text is the
/// topic editor before a run, the steering note while the run is paused,
/// the closed field's notice while the agents work, and the ending's
/// detail after. The capsule's height is fixed, so the editors scroll
/// inside what the box leaves them.
struct PerchPromptBox: View {
    @Bindable var controller: RelayController

    static let textInset = Perch.s(12)
    private static let corner = Perch.s(16)

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(4)) {
            ZStack(alignment: .topLeading) {
                switch controller.stage {
                case .setup, .compose:
                    openingEditor
                case .running:
                    if controller.isSteering { steering } else { closedField }
                case .finished:
                    ending
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Self.textInset)
            // The replies' dots fly to and from here in every stage.
            .background {
                PromptTransferProbe(source: controller.promptTransferSource)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            HStack(spacing: Perch.s(10)) {
                PerchLayoutSegments(controller: controller)
                    .disabled(controller.stage == .running)
                Spacer(minLength: 0)
                PerchConsoleActions(controller: controller)
            }
            .frame(height: Perch.actionDiameter)
            .padding(.horizontal, Perch.s(7))
        }
        .padding(.top, Perch.s(6))
        .padding(.bottom, Perch.s(6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Perch.paper.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Self.corner).stroke(Perch.chipEdge, lineWidth: 1))
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

    /// The note editor, with what its keys do under it. The line costs the
    /// note its third visible row; a longer note scrolls.
    private var steering: some View {
        VStack(alignment: .leading, spacing: Perch.s(3)) {
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
            PerchRunLine(controller: controller)
        }
    }

    private var hasNoteFeedback: Bool {
        controller.steeringQueued || controller.steeringInFlight != nil || controller.lastReceipt != nil
    }

    /// The field is closed while the agents work: how to recover from a
    /// hold, or the reminder not to type in the apps, and what has become
    /// of a note.
    private var closedField: some View {
        VStack(alignment: .leading, spacing: Perch.s(4)) {
            if let block = controller.block, !controller.stopRequested {
                let recovery = block.recovery(names: controller.names)
                Text(recovery)
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.red)
                    .lineLimit(2)
                    .help(recovery)
                    .transition(.opacity)
            } else if !hasNoteFeedback {
                Text("Pause before typing in either conversation.")
                    .font(Perch.text(13))
                    .foregroundStyle(Perch.placeholder)
                    .lineLimit(1)
            }
            if hasNoteFeedback {
                PerchRunLine(controller: controller)
            }
            if controller.steeringQueued {
                Text(controller.steeringText)
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.secondary)
                    .lineLimit(2)
                    .help(controller.steeringText)
            }
        }
        .padding(.vertical, GrowingTextEditor.insetHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: After a run

    /// The status line has how the run ended; the count, the clock, and the
    /// last note's record go where the text was.
    private var ending: some View {
        let detail = controller.lastReport?.detail(names: controller.names, duration: controller.lastRunDuration,
                                                   timeout: config.timeout) ?? ""
        return VStack(alignment: .leading, spacing: Perch.s(4)) {
            Text(detail)
                .font(Perch.text(12))
                .foregroundStyle(Perch.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(detail)
            if let receipt = controller.lastReceipt {
                PerchReceiptLine(controller: controller, receipt: receipt)
            }
        }
        .padding(.vertical, GrowingTextEditor.insetHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - The surface labels

/// One line under the prompt box: at each end, what the side's window is
/// and what runs in it — the app and its surface as a product name
/// ("ChatGPT Chat", "Codex", "Claude Code"), then the model, with its
/// effort after it a shade lighter ("Fable 5 Extra"), as the sweep reads
/// them. ChatGPT's stands at the leading end and Claude's at the trailing,
/// under their icons. A connected side is read from its own window as the
/// latest sweep saw it (SideSetup.connectedCandidate), so a model switched
/// in the app shows here; an unconnected one from the window the sweep
/// would choose. An end stays empty while nothing is known — the icon says
/// which app it is.
struct PerchSurfaceLabels: View {
    let controller: RelayController

    /// One side's label in its parts. The product and model share the
    /// line's color, a dot between them; the effort, split from the
    /// model line (splitEffort), follows the model after a space, lighter.
    private struct Reading: Equatable {
        var product: String?
        var model: String?
        var effort: String?

        var isEmpty: Bool { product == nil && model == nil }
        /// The parts in the line's own color, up to the effort.
        var lead: String { [product, model].compactMap { $0 }.joined(separator: " \u{00B7} ") }
        /// The whole line, for the tooltip and the accessible name.
        var text: String { effort.map { "\(lead) \($0)" } ?? lead }
    }

    var body: some View {
        let readings = [Speaker.chatgpt, .claude].map(reading(for:))
        HStack(spacing: Perch.s(12)) {
            label(readings[0], alignment: .leading)
            label(readings[1], alignment: .trailing)
        }
        // The line starts and ends where the prompt's text does.
        .padding(.horizontal, PerchPromptBox.textInset)
        .frame(height: Perch.s(15))
        .animation(Perch.fade, value: readings)
    }

    private func label(_ reading: Reading, alignment: Alignment) -> some View {
        var text = Text(reading.lead).foregroundStyle(Perch.secondary)
        if let effort = reading.effort {
            text = text + Text(" \(effort)").foregroundStyle(Perch.muted)
        }
        return text
            .font(Perch.text(11))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(reading.text)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityHidden(reading.isEmpty)
    }

    /// What one side's label says; empty when nothing is known of it.
    private func reading(for speaker: Speaker) -> Reading {
        let side = controller.setup.state[speaker]
        let status = speaker == .chatgpt ? controller.chatgptStatus : controller.claudeStatus
        let surface: String?
        let line: String?
        if let connection = side.connection {
            let live = side.connectedCandidate
            surface = live?.identity.surface ?? connection.identity.surface
            line = live?.model ?? connection.model
        } else {
            surface = status.surface
            line = status.model
        }
        var reading = Reading(product: Self.productName(app: status.appName, surface: surface))
        if let line {
            let selectors = speaker == .chatgpt ? config.chatgptSelectors : config.claudeSelectors
            let split = splitEffort(line, selectors: selectors)
            reading.model = split.model
            reading.effort = split.effort
            // A model with no surface read still says whose it is.
            if reading.product == nil { reading.product = status.appName }
        }
        return reading
    }

    /// Surfaces that are products of their own, named without the app.
    private static let standaloneSurfaces: Set<String> = ["Codex"]

    /// The surface as a product: the app's name with the surface after it
    /// ("Claude Code", "ChatGPT Work"), or the surface alone where it is a
    /// product of its own ("Codex"). nil where no surface was read.
    static func productName(app: String, surface: String?) -> String? {
        guard let surface else { return nil }
        return standaloneSurfaces.contains(surface) ? surface : "\(app) \(surface)"
    }
}

// MARK: - The window arrangement

extension LayoutChoice {
    var symbol: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        case .keepPositions: return "macwindow.on.rectangle"
        }
    }

    var actionHelp: String {
        switch self {
        case .sideBySide: return "Move both windows side by side now"
        case .stacked: return "Move both windows into a stack now"
        case .keepPositions: return "Leave both windows where they are"
        }
    }
}

/// The three arrangements in one glass capsule at the toolbar's leading
/// end. A choice applies at once, as it did on the arrange step, and stands
/// for windows connected later (SetupController.applyIfPending). The glass
/// is a background layer, as the panel's own is: glass wrapped around
/// content makes AppKit read a drag inside it as a window move
/// (PanelWindowSurface).
struct PerchLayoutSegments: View {
    let controller: RelayController
    @Namespace private var thumb
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = controller.setup.state.layout
        HStack(spacing: Perch.s(2)) {
            ForEach(LayoutChoice.allCases, id: \.self) { layout in
                Button { controller.setup.choose(layout) } label: {
                    Image(systemName: layout.symbol)
                        .font(Perch.text(13))
                        .foregroundStyle(selected == layout ? Perch.ink : Perch.secondary)
                        .frame(width: Perch.s(34), height: Perch.s(24))
                        .background {
                            if selected == layout {
                                Capsule().fill(Perch.paper)
                                    .overlay(Capsule().stroke(Perch.chipEdge, lineWidth: 1))
                                    .matchedGeometryEffect(id: "selection", in: thumb)
                            }
                        }
                        .perchHover(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(layout.actionHelp)
                .accessibilityLabel(layout.title)
                .accessibilityAddTraits(selected == layout ? .isSelected : [])
            }
        }
        .padding(Perch.s(3))
        .background(Color.clear.glassEffect(.regular, in: Capsule()))
        .opacity(isEnabled ? 1 : 0.5)
        .animation(reduceMotion ? nil : Perch.spring, value: selected)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window arrangement. Choices apply immediately.")
    }
}

// MARK: - The actions

/// The toolbar's trailing end. Before a run it is Send, or the way to open
/// the apps while one is closed; during a run Pause and Stop, or the paused
/// run's three; after it, the way back to the editor.
struct PerchConsoleActions: View {
    let controller: RelayController

    private var setup: SetupController { controller.setup }

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            switch controller.stage {
            case .setup, .compose:
                if closedApps.isEmpty { send } else { open }
            case .running:
                if controller.isSteering { paused } else { running }
            case .finished:
                finished
            }
        }
        .fixedSize()
    }

    private var closedApps: [Speaker] {
        [Speaker.chatgpt, .claude].filter { setup.state[$0].presence == .notRunning }
    }

    /// Apps are opened only when asked: here, or by a click on an icon.
    private var open: some View {
        let title = closedApps.count == 2 ? "Open both apps" : "Open \(setup.name(closedApps[0]))"
        return PerchCapsuleButton(title: title, icon: "arrow.up.right") { setup.launchBoth() }
            .help("Open whichever app isn\u{2019}t open yet")
    }

    private var send: some View {
        PerchCapsuleButton(title: controller.sendLabel, icon: "paperplane.fill") { controller.start() }
            .disabled(controller.sendBlocker != nil)
            .keyboardShortcut(.defaultAction)
            .help(controller.sendBlocker
                  ?? "Send the topic to \(controller.appName(controller.firstSpeaker)) and start relaying")
    }

    private var running: some View {
        HStack(spacing: Perch.s(8)) {
            PerchRevealButton(title: controller.steeringQueued ? "Edit note" : "Pause to steer",
                              icon: "pause.fill") { controller.beginSteering() }
                .disabled(controller.isSteeringPending || controller.stopRequested)
                .help(controller.isSteeringPending
                      ? "Pausing after the current handoff"
                      : "Pause at a safe handoff and write a note for the next side")
            PerchRevealButton(title: "Stop", icon: "stop.fill", prominent: false,
                              labelClearance: 1.5 * Perch.actionDiameter + Perch.s(16)) { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
        }
    }

    private var paused: some View {
        HStack(spacing: Perch.s(8)) {
            PerchTextButton(title: "Resume without note") { controller.resumeWithoutNote() }
            PerchCapsuleButton(title: "Stop", style: .glass, icon: "stop.fill") { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
            PerchCapsuleButton(title: "Send note & continue", icon: "arrow.up") { controller.sendSteering() }
                .disabled(!controller.steeringHasText)
                .help(controller.nextRecipient.map { "The note goes to \($0) with the next handoff" }
                      ?? "The note goes with the next handoff")
        }
    }

    /// One way on. The connections are held, and both are read again before
    /// Send is offered; a conversation changed in the apps meanwhile is
    /// picked up the way any other is.
    private var finished: some View {
        PerchCapsuleButton(title: "New topic", icon: "arrow.counterclockwise") { controller.anotherTopicHere() }
            .keyboardShortcut(.defaultAction)
            .help("Write another topic for these conversations; their context carries on")
    }
}

#if DEBUG
#Preview("Console · several conversations") {
    // The preview engine shows two windows on each side, so neither is
    // connected until one is chosen from its icon.
    PerchConsoleView(controller: RelayController(engine: PerchPreviewEngine()))
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Console · both connected") {
    let controller = RelayController(engine: PerchPreviewEngine())
    controller.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    controller.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeConversation)
    controller.topic = "Pricing by seat or by usage"
    return PerchConsoleView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Console · Code session") {
    // Claude's side is a Code session: named as one under the prompt, with
    // the bare model its popup announces.
    let controller = RelayController(engine: PerchPreviewEngine())
    controller.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    controller.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeCode)
    return PerchConsoleView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Console · ChatGPT closed") {
    var closed = PerchPreviewEngine.bothReady
    closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
    return PerchConsoleView(controller: RelayController(engine: PerchPreviewEngine(readiness: closed)))
        .padding(24)
        .background(Color(white: 0.75))
}
#endif

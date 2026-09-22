// The console the app shows: the prompt from the start, with no steps
// before it. The participants stand at the capsule's ends as they always
// have; between them, the topic line sits above a prompt box, and the box
// holds the text over a toolbar row — the window arrangement at its
// leading end, the actions at its trailing end. The topic line says who
// goes first, and once the run has started, what it is about. Under the
// box, one line says what needs saying — what a side still needs, what
// the apps are doing, how the run ended — and when nothing does, each
// side's surface and model as the sweep reads them. Every stage shares
// that frame: the topic editor, then the run with the field closed or the
// steering note open in it, then the ending.
//
// The icons open the apps, the arrangement applies as it is chosen, each
// side is connected as SetupController.connectIfUnambiguous has it, and
// the line under the box names the next thing a side needs. The session's
// options are on the status item's menu.

import SwiftUI

struct PerchConsoleView: View {
    let controller: RelayController
    var width: CGFloat = Perch.widgetWidth
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: Perch.s(14)) {
            PerchParticipant(controller: controller, speaker: .chatgpt)
            VStack(alignment: .leading, spacing: Perch.s(5)) {
                PerchTopicLine(controller: controller)
                PerchPromptBox(controller: controller)
                PerchConsoleStatus(controller: controller)
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

// MARK: - The topic line

/// The line above the prompt: who goes first, as chosen on the Send pill,
/// and once the on-device model has written one sentence on what the run
/// is about from the prompt (TopicSummarizer), that sentence. Who went
/// first stays on the line until then, and for good where the model
/// cannot write one. The sentence outlasts the run: it names the ending
/// until a new topic is written.
struct PerchTopicLine: View {
    let controller: RelayController

    private struct Line: Equatable {
        var text: String
        var isTopic: Bool
    }

    var body: some View {
        let line = self.line
        Text(line.text)
            .font(Perch.text(12, line.isTopic ? .medium : .regular))
            .foregroundStyle(line.isTopic ? Perch.ink : Perch.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(line.text)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The line starts where the prompt's text does.
            .padding(.horizontal, PerchPromptBox.textInset)
            .frame(height: Perch.s(17))
            .animation(Perch.fade, value: line)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.isTopic ? "Topic" : "Who goes first")
            .accessibilityValue(line.text)
    }

    private var line: Line {
        if controller.stage != .compose, let summary = controller.topicSummary {
            return Line(text: summary, isTopic: true)
        }
        return Line(text: "\(controller.appName(controller.firstSpeaker)) goes first", isTopic: false)
    }
}

// MARK: - The status line

/// The line under the prompt box: what needs saying, whatever the stage
/// — what a side still needs before Send, a start the engine refused,
/// what the apps are doing during a run with its turn and clock at the
/// trailing end, how the run ended — and when nothing does, each side's
/// surface and model (PerchSurfaceLabels).
struct PerchConsoleStatus: View {
    let controller: RelayController

    var body: some View {
        let status = self.status
        HStack(spacing: Perch.s(8)) {
            if let status {
                Text(status.text)
                    .font(Perch.text(12))
                    .foregroundStyle(status.isProblem ? Perch.red : Perch.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(status.text)
                    .contentTransition(.opacity)
                    .perchShimmer(active: isWorking)
                    .transition(.opacity)
                Spacer(minLength: 0)
                if controller.stage == .running {
                    PerchRunMetadata(controller: controller)
                        .fixedSize()
                        .transition(.opacity)
                }
            } else {
                PerchSurfaceLabels(controller: controller)
                    .transition(.opacity)
            }
        }
        // The line starts and ends where the prompt's text does.
        .padding(.horizontal, PerchPromptBox.textInset)
        .frame(height: Perch.s(17))
        .animation(Perch.fade, value: status)
        .accessibilityElement(children: status == nil ? .contain : .combine)
    }

    /// Nil when everything is idle and nothing is wrong: the labels' turn.
    private var status: SetupNotice? {
        switch controller.stage {
        case .compose:
            // A start the engine refused outranks what the sweeps say: it
            // is the answer to the click just made.
            if let failed = controller.failedStart { return SetupNotice(text: failed, isProblem: true) }
            return controller.setup.notice
        case .running:
            // The open field's keys need saying more than the apps' state,
            // which the turn line and the icons carry meanwhile.
            if controller.isSteering, !controller.stopRequested, controller.block == nil {
                return SetupNotice(text: controller.steeringHint, isProblem: false)
            }
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

extension RelayController {
    /// What the open field's keys do, as the line under the prompt while
    /// the note is written (PerchConsoleStatus): with nothing in it yet,
    /// whom the note would be for and how to resume without one; with
    /// words, how to send them and how to clear them.
    var steeringHint: String {
        let side = nextRecipient
        if steeringHasText {
            return side.map { "Return sends it to \($0) \u{00B7} Esc clears it" }
                ?? "Return sends it with the next handoff \u{00B7} Esc clears it"
        }
        return side.map { "Write a note for \($0) \u{00B7} Return or Esc resumes without one" }
            ?? "Write a note \u{00B7} Return or Esc resumes without one"
    }

    /// The one running sentence: what is happening in the apps now, as the
    /// line under the prompt (PerchConsoleStatus).
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
            let turn = controller.limitTurns ? "Turn \(controller.currentTurn) of \(controller.turns)"
                : "Turn \(controller.currentTurn)"
            let phase = controller.isSteering ? "Paused" : controller.conversation
            Text("\(phase) · \(turn) · \(runClock(controller.elapsedRunDuration(at: context.date)))")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - The prompt box

/// The box under the topic line: text over a toolbar row. The text is the
/// topic editor before a run and, read-only, until the opening has set
/// off from it; then the steering note while the run is paused, the
/// closed field's notice while the agents work, and the ending's detail
/// after. The capsule's height is fixed, so the editors scroll inside
/// what the box leaves them.
struct PerchPromptBox: View {
    @Bindable var controller: RelayController

    static let textInset = Perch.s(12)
    private static let corner = Perch.s(16)

    /// What stands in the text's place. One value for the prompt as
    /// written, before and just after Send, so the editor keeps its
    /// identity — its scroll position, its selection — across the start.
    private enum Field {
        case opening, steering, closed, ending
    }

    private var field: Field {
        switch controller.stage {
        case .compose: return .opening
        case .running:
            if controller.isSteering { return .steering }
            return controller.openingStillVisible ? .opening : .closed
        case .finished: return .ending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(4)) {
            ZStack(alignment: .topLeading) {
                switch field {
                case .opening:
                    openingEditor.disabled(controller.isRunning)
                case .steering:
                    steering
                case .closed:
                    closedField
                case .ending:
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
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Perch.paper))
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

/// The line under the prompt box while nothing needs saying there
/// (PerchConsoleStatus): at each end, what the side's window is and what
/// runs in it — the app and its surface as a product name ("ChatGPT
/// Chat", "Codex", "Claude Code"), then the model, with its effort after
/// it a shade lighter ("Fable 5 Extra"), as the sweep reads them.
/// ChatGPT's stands at the leading end and Claude's at the trailing,
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

/// The three arrangements in one flat control at the toolbar's leading
/// end, as tall as the actions beside it and with the prompt box's kind
/// of corner (Perch.controlCorner). A choice applies at once, and stands
/// for windows connected later (SetupController.applyIfPending).
///
/// A well with a paper thumb on the chosen segment and hairlines between
/// the others that hide beside it, drawn by hand: NSSegmentedControl fills
/// its selection with the accent color outside an NSToolbar, and its
/// selection jumps on mouse-up where this one slides.
struct PerchLayoutSegments: View {
    let controller: RelayController
    private static let inset = Perch.s(3.5)
    private static let shape = RoundedRectangle(cornerRadius: Perch.controlCorner)
    private static let thumbShape = RoundedRectangle(cornerRadius: Perch.controlCorner - inset)
    @Namespace private var thumb
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layouts = LayoutChoice.allCases
        let selected = controller.setup.state.layout
        let selectedIndex = layouts.firstIndex(of: selected)
        HStack(spacing: 0) {
            ForEach(layouts.indices, id: \.self) { index in
                let layout = layouts[index]
                if index > 0 {
                    Rectangle().fill(Perch.ink.opacity(0.2))
                        .frame(width: 1, height: Perch.s(14))
                        .opacity(selectedIndex == index || selectedIndex == index - 1 ? 0 : 1)
                        .accessibilityHidden(true)
                }
                Button { controller.setup.choose(layout) } label: {
                    Image(systemName: layout.symbol)
                        .font(Perch.text(14))
                        .foregroundStyle(Perch.ink)
                        .frame(width: Perch.s(36), height: Perch.s(25))
                        .background {
                            if selected == layout {
                                Self.thumbShape.fill(Perch.paper)
                                    .matchedGeometryEffect(id: "selection", in: thumb)
                            }
                        }
                        .perchHover(Self.thumbShape)
                        .contentShape(Self.thumbShape)
                }
                .buttonStyle(.plain)
                .help(layout.actionHelp)
                .accessibilityLabel(layout.title)
                .accessibilityAddTraits(selected == layout ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .background(Self.shape.fill(Perch.well))
        .opacity(isEnabled ? 1 : 0.5)
        .animation(reduceMotion ? nil : Perch.spring, value: selected)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window arrangement. Choices apply immediately.")
    }
}

// MARK: - The actions

/// The toolbar's trailing end. Before a run it is Send, with who goes
/// first inside it, or the way to open the apps while one is closed;
/// during a run Pause and Stop, or the paused run's Resume — Send note
/// once there is one — and Stop; after it, the way back to the editor.
struct PerchConsoleActions: View {
    @Bindable var controller: RelayController

    private var setup: SetupController { controller.setup }

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            switch controller.stage {
            case .compose:
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

    /// Send and the choice of who receives the topic, in one pill.
    private var send: some View {
        PerchSendPill(sides: [Speaker.chatgpt, .claude].map { side in
            PerchSendPill.Side(speaker: side, name: controller.appName(side),
                               bundleID: side == .chatgpt ? config.chatgptBundleID : config.claudeBundleID)
        }, first: $controller.firstSpeaker, blocker: controller.sendBlocker) { controller.start() }
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
            PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
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

// MARK: - Canvases

// Every canvas runs on PerchPreviewEngine, so the controls do what they
// do in the app — an icon opens an app or connects a conversation, Send
// starts a run, Stop ends it at the next handoff and leaves the summary,
// Pause to steer holds it and opens the field, Return sends the note —
// and nothing reaches either app.

#if DEBUG
/// Both sides connected, with the form filled in so Send has something
/// to send.
private func connectedController(_ engine: PerchPreviewEngine = PerchPreviewEngine()) -> RelayController {
    let controller = RelayController(engine: engine)
    controller.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    controller.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeConversation)
    controller.topic = "Pricing by seat or by usage"
    return controller
}

private func canvas(_ controller: RelayController) -> some View {
    PerchConsoleView(controller: controller)
        .padding(24)
        .background(Color(white: 0.75))
}

#Preview("Console · several conversations") {
    // The preview engine shows two windows on each side, so neither is
    // connected until one is chosen from its icon.
    canvas(RelayController(engine: PerchPreviewEngine()))
}

#Preview("Console · both connected") {
    canvas(connectedController())
}

#Preview("Console · Code session") {
    // Claude's side is a Code session: named as one under the prompt, with
    // the bare model its popup announces.
    let controller = RelayController(engine: PerchPreviewEngine())
    controller.setup.connect(.chatgpt, to: PerchPreviewEngine.Windows.chatgptConversation)
    controller.setup.connect(.claude, to: PerchPreviewEngine.Windows.claudeCode)
    return canvas(controller)
}

#Preview("Console · ChatGPT closed") {
    var closed = PerchPreviewEngine.bothReady
    closed.chatgpt = SideStatus(appName: "ChatGPT", state: .missing, headline: "Not running")
    return canvas(RelayController(engine: PerchPreviewEngine(readiness: closed)))
}

#Preview("Console · Claude not installed") {
    var missing = PerchPreviewEngine.bothReady
    missing.claude = SideStatus(appName: "Claude", state: .missing, headline: "Not running")
    return canvas(RelayController(engine: PerchPreviewEngine(readiness: missing,
                                                             installed: [.chatgpt: true, .claude: false])))
}

#Preview("Console · long topic") {
    let controller = connectedController()
    controller.topic = Array(repeating: "Compare pricing by seat and by usage. Consider predictability, fairness, and how each option grows with a team.", count: 8)
        .joined(separator: "\n\n")
    return canvas(controller)
}

#Preview("Console · running") {
    // Opens on turn 4 of 10, Claude writing. The topic line says who went
    // first for a second, then the sentence a stand-in writes, as the
    // model would.
    let controller = connectedController(PerchPreviewEngine(turn: 4))
    controller.limitTurns = true
    controller.turns = 10
    controller.summarize = { _ in
        try? await Task.sleep(for: .seconds(1.2))
        return "Whether to price by seat or by usage"
    }
    controller.start()
    return canvas(controller)
}

#Preview("Console · running (model unavailable)") {
    // No sentence comes, so the line keeps saying who went first.
    let controller = connectedController(PerchPreviewEngine(turn: 4))
    controller.summarize = { _ in nil }
    controller.start()
    return canvas(controller)
}

#Preview("Console · paused (field open, holding)") {
    // Claude's reply is ready to capture, so the pause holds at once.
    let controller = connectedController(PerchPreviewEngine(turn: 4, atHandoff: true))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    return canvas(controller)
}

#Preview("Console · paused (queued note)") {
    // The note is in the mailbox; it rides the handoff after Claude's
    // reply, and its echo the one after that.
    let controller = connectedController(PerchPreviewEngine(turn: 4))
    controller.start()
    controller.beginSteering()
    controller.setSteeringText("Push on the pricing question before you wrap up.")
    controller.sendSteering()
    return canvas(controller)
}

#Preview("Console · finished") {
    // A run's leavings, set directly: what the console shows once the
    // engine has posted .finished.
    let controller = connectedController()
    controller.setup.runStarted()
    controller.currentTurn = 6
    controller.lastReport = RunReport(outcome: .completed, repliesCaptured: 6)
    controller.lastRunDuration = 272
    controller.chatgptConversation = .ended
    controller.claudeConversation = .ended
    return canvas(controller)
}

#Preview("Console · finished (stopped, played)") {
    // A short run stopped from the actions: Stop dims and the line says the
    // end is coming, then the summary reads "Run stopped". Both sides sign
    // off from turn 8, so left alone it completes instead.
    let controller = connectedController(PerchPreviewEngine(pace: .seconds(2), signOffAt: 8))
    controller.start()
    return canvas(controller)
}

#Preview("Console · handoff (animated)") {
    // Replies take two seconds and nobody signs off, so the transfer plays
    // over and over until Stop.
    let controller = connectedController(PerchPreviewEngine(pace: .seconds(2.2)))
    controller.start()
    return canvas(controller)
}

#Preview("Avatars (icon and fallback)") {
    // The first wears whatever Claude Desktop's icon is on this Mac; the
    // second names no installed app, so it is the initial-in-a-circle
    // fallback the column uses when an app is missing.
    HStack(spacing: Perch.s(24)) {
        PerchAvatar(bundleID: config.claudeBundleID, initial: "C", feather: Perch.claudeFeather)
        PerchAvatar(bundleID: "com.example.not-installed", initial: "C", feather: Perch.claudeFeather)
    }
    .padding(Perch.s(24))
    .background(Perch.paper)
}
#endif

// The composer: one card whose first two lines are the conversation's setup
// — the shape tabs and the selected shape's instructions — closed off by a
// hairline, with the person's own words below the line and the actions at
// the foot. The arrangement is the converged proposal
// (docs/design-proposals/chat-composer/converged-composer.html): the shape
// choice is input, so it lives on the composing surface, and the card keeps
// its anatomy across states — in a run the setup zone folds into a one-line
// context row above the same hairline, and the editor becomes the steering
// field (typing is what begins a steer, RelayController.setSteeringText).
// The foot follows the chat apps' own composers: the run options are bare
// glyphs that grow a label when they are on, and one filled circle is the
// primary action. See PerchPanelView for the panel.

import SwiftUI

/// The card: structure only. The zone, the editor, and the toolbar are
/// their own observation scopes so a keystroke invalidates the text and the
/// button that watches it, never the tabs or the perches above.
struct PerchComposer: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.cardGap) {
            PerchConfigZone(controller: controller)
            PerchComposerEditor(controller: controller)
            PerchComposerToolbar(controller: controller)
        }
        .padding(Perch.boxInset)
        .background(RoundedRectangle(cornerRadius: Perch.boxCorner).fill(Perch.well))
    }
}

/// The setup zone above the hairline: idle, the shape tabs and — for any
/// shape but Free chat — the instruction preview; in a run, the one-line context row (or the amber
/// hold notice while a steer is being written). The hairline itself is
/// drawn here so the zone and its rule always move together.
private struct PerchConfigZone: View {
    let controller: RelayController
    /// The tab thumb's coordinate space: every tab is a source in it, and
    /// the thumb follows whichever one the selection names.
    @Namespace private var tabSpace

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.cardGap) {
            if controller.isRunning {
                // Overlaid, not stacked, so the crossfade never shows both
                // rows at once and the card holds its height through it.
                ZStack(alignment: .leading) {
                    if controller.isSteering {
                        holdNotice.transition(.opacity)
                    } else {
                        contextLine.transition(.opacity)
                    }
                }
                .animation(Perch.fade, value: controller.isSteering)
                hairline
            } else {
                shapeTabs
                // Free chat has no instructions to preview, so it shows
                // none — and no rule to close a zone that is only the tabs.
                // Choosing a shape brings both in, settling down from the
                // tabs, and the editor gives up exactly their height
                // (PerchComposerEditor): the card holds its size, and only
                // the words move down to make room.
                if !controller.isFreeChat {
                    previewRow
                        .frame(height: Perch.previewHeight, alignment: .topLeading)
                        .transition(.opacity.combined(with: .offset(y: -Perch.s(6))))
                    hairline
                        .transition(.opacity)
                }
            }
        }
    }

    /// The rule that closes the zone.
    private var hairline: some View {
        Rectangle()
            .fill(Perch.hairline)
            .frame(height: 1)
    }

    // MARK: The shape tabs

    /// The quick set is fixed: Free chat, then the first two saved shapes —
    /// Brainstorm and Debate as shipped — with More owning the rest of the
    /// collection. A stable row teaches the shapes; a learned one would
    /// reshuffle under the hand that just learned it.
    private var quickTemplates: [ConversationTemplate] {
        Array(conversationTemplates.prefix(2))
    }

    private var overflowTemplates: [ConversationTemplate] {
        Array(conversationTemplates.dropFirst(2))
    }

    /// Whether the active shape lives behind More rather than in the row.
    private var moreHoldsSelection: Bool {
        !controller.isFreeChat
            && !quickTemplates.contains { $0.name == controller.conversation }
    }

    /// More's slot in the thumb's space — a constant, because its label
    /// changes to name whatever shape it holds.
    private static let moreTabID = "more"

    /// Which tab the thumb sits under: a fixed shape's own name, or More's
    /// slot when the shape lives behind it.
    private var selectedTab: String {
        moreHoldsSelection ? Self.moreTabID : controller.conversation
    }

    /// One track, the shapes as text in equal cells, and a single paper
    /// thumb that springs to the chosen one, with the selection moving
    /// rather than each cell lighting up on its own. The thumb is flat: the
    /// system glass casts a shadow under the row, and a control this small
    /// should sit in the card, not float over it. Names alone: the shapes
    /// are words, and a glyph per word made the row read as a toolbar.
    private var shapeTabs: some View {
        HStack(spacing: 0) {
            shapeTab(RelayController.freeConversation)
            ForEach(quickTemplates) { template in
                shapeTab(template.name)
            }
            moreTab
        }
        .padding(Perch.s(3))
        .background {
            // The thumb takes the selected tab's frame through the shared
            // namespace, so a change of selection is a move, not a swap.
            Capsule()
                .fill(Perch.paper)
                .matchedGeometryEffect(id: selectedTab, in: tabSpace, isSource: false)
        }
        .background(Capsule().fill(Perch.track))
    }

    private func shapeTab(_ name: String) -> some View {
        Button {
            choose(name)
        } label: {
            tabLabel(name, id: name, selected: selectedTab == name)
        }
        .buttonStyle(.plain)
        .help(name == RelayController.freeConversation
              ? "Open conversation — the topic is the whole opening message"
              : "Open with the \(name) instructions")
    }

    /// A cell in the track: the name, ink when it is the selection and a
    /// step quieter otherwise, darkening under the pointer. The cell is a
    /// source for the thumb, so it is measured whole — padding included.
    private func tabLabel(_ text: String, id: String, selected: Bool,
                          menu: Bool = false) -> some View {
        HStack(spacing: Perch.s(4)) {
            Text(text)
                .font(Perch.text(12, .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if menu {
                Image(systemName: "chevron.down")
                    .font(.system(size: Perch.s(7), weight: .semibold))
            }
        }
        .padding(.horizontal, Perch.s(10))
        .frame(maxWidth: .infinity)
        .frame(height: Perch.s(24))
        .perchHoverInk(idle: selected ? Perch.ink : Perch.secondary, active: Perch.ink)
        .contentShape(Capsule())
        .matchedGeometryEffect(id: id, in: tabSpace)
    }

    /// Every selection springs, so the thumb travels and the More cell's
    /// name changes under it in the same motion.
    private func choose(_ name: String) {
        withAnimation(Perch.spring) { controller.selectConversation(name) }
    }

    /// More owns everything the row does not: the remaining shapes, writing
    /// from scratch, and the way into Settings. A shape chosen here takes
    /// over the cell's label and the thumb comes to rest under it, so the
    /// current selection is always visible without the row allocating a
    /// cell to every possible shape.
    private var moreTab: some View {
        Menu {
            ForEach(overflowTemplates) { template in
                Button(template.name) { choose(template.name) }
            }
            Button("Write from scratch") { choose(RelayController.customConversation) }
            Divider()
            Button("Manage shapes…") { controller.openSettings() }
        } label: {
            tabLabel(moreHoldsSelection ? controller.conversation : "More",
                     id: Self.moreTabID, selected: moreHoldsSelection, menu: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .help("The other shapes, a from-scratch prompt, and the shape editor")
    }

    // MARK: The instruction preview

    /// Under the tabs, what the selected shape will actually say: the
    /// template's instructions as quiet mono text, held to two lines with
    /// the rest behind an ellipsis and the whole text in the tooltip under
    /// the pointer. Plain text on purpose — no band, no control around it —
    /// so it reads as the system's part of the opening message, sent as
    /// written rather than something to edit here: the saved shape is
    /// edited in Settings, and a one-off prompt is written under Custom,
    /// whose editor takes the band's place below.
    @ViewBuilder
    private var previewRow: some View {
        if controller.selectedTemplate == nil, !controller.isFreeChat {
            Text("Writing the opening message from scratch")
                .font(Perch.text(11))
                .foregroundColor(Perch.muted)
                .padding(.horizontal, Perch.s(2))
        } else {
            // The text sets its own height: a SwiftUI Text offered a height
            // fits itself to it, and the slot below is measured with AppKit
            // metrics that can land a hair under SwiftUI's own two lines —
            // enough to drop the second line for an ellipsis. So the frame
            // reserves the space and the words fill it on their own terms.
            Text(previewText)
                .font(Perch.mono(Perch.previewSize))
                .foregroundColor(Perch.previewInk)
                .lineSpacing(Perch.previewLineSpacing)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Perch.s(2))
                .help(previewBody)
        }
    }

    private var previewBody: String {
        controller.selectedTemplate?.body ?? ""
    }

    /// The body run together: the preview is a two-line peek at the words,
    /// not at their layout, so a paragraph break must not spend a whole
    /// line on nothing. The tooltip keeps the body as written.
    private var previewText: String {
        previewBody.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: The zone mid-run

    /// The setup zone folded to one line: the loaded shape and the run
    /// options, readable but no longer controls — a run owns them.
    private var contextLine: some View {
        HStack(spacing: Perch.s(6)) {
            Image(systemName: PerchShapeIcons.icon(for: controller.conversation))
                .font(.system(size: Perch.s(10), weight: .medium))
            Text(controller.conversation)
                .font(Perch.text(11, .medium))
            Text("·")
                .foregroundColor(Perch.chipEdge)
            Text(optionsSummary)
                .font(Perch.text(11))
        }
        .foregroundColor(Perch.muted)
        .padding(.horizontal, Perch.s(2))
    }

    private var optionsSummary: String {
        var parts = [controller.limitTurns ? "\(controller.turns) turns" : "Auto"]
        if controller.tileWindows { parts.append("Tile") }
        return parts.joined(separator: " · ")
    }

    /// The side whose reply the note will travel with: the one writing now,
    /// or the one whose finished reply a pause is holding.
    private var replier: String? {
        switch (controller.chatgptConversation, controller.claudeConversation) {
        case (.chatting, _), (.replied, _): return controller.chatgptStatus.appName
        case (_, .chatting), (_, .replied): return controller.claudeStatus.appName
        default: return nil
        }
    }

    /// The side that reads the note first: the reply goes to the other
    /// side, and the note goes with it.
    private var reader: String? {
        guard let replier else { return nil }
        return replier == controller.chatgptStatus.appName
            ? controller.claudeStatus.appName
            : controller.chatgptStatus.appName
    }

    /// While a steer is being written the zone says, in plain words, who is
    /// writing and where the note will go. It takes the context line's own
    /// row — an amber dot where the shape's glyph sits, the text in the
    /// quiet amber, no band — so the card keeps its height when the notice
    /// replaces the context and nothing below it jumps.
    private var holdNotice: some View {
        HStack(spacing: Perch.s(6)) {
            Circle()
                .fill(Perch.amber)
                .frame(width: Perch.s(7), height: Perch.s(7))
            Text(holdText)
                .font(Perch.text(11))
                .foregroundColor(Perch.amberText)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Perch.s(2))
        .animation(Perch.fade, value: holdText)
    }

    private var holdText: String {
        if controller.isHolding {
            if let replier, let reader {
                return "Paused. Your note will go to \(reader) when you resume."
            }
            return "Paused. Your note will go out when you resume."
        }
        if let replier, let reader {
            return "Pausing when \(replier) is done… Your note will go to \(reader) after."
        }
        return "Pausing after this reply… Your note will go out after."
    }
}

/// The editor in its three modes: topic (Free chat included), full prompt,
/// steering note. Its own scope so typing invalidates only this view and
/// the toolbar's morphing button.
private struct PerchComposerEditor: View {
    @Bindable var controller: RelayController

    var body: some View {
        if controller.isRunning {
            GrowingTextEditor(text: steeringBinding,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholder: controller.steeringText.isEmpty
                                  ? "Add a direction while they work…" : nil,
                              minimumLines: 2, maximumLines: 8,
                              onSubmit: { controller.sendSteering() },
                              onEscape: { controller.cancelSteer() })
                .help("Type a note to steer the conversation. We'll pause so you can finish it — Return sends the note, Esc clears it")
        } else if !controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.topic,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 3, maximumLines: 12,
                              // Free chat shows no preview, so the editor
                              // holds the preview zone's height itself and
                              // the card is one size for every shape.
                              extraMinimumHeight: controller.isFreeChat
                                  ? Perch.previewZoneHeight : 0,
                              onSubmit: { controller.start() })
        } else {
            // Prose mode: Return breaks the line, as a prompt editor should;
            // Run is the button's job here. The same three lines as the
            // topic field, so switching to Custom moves no edge of the card.
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 3, maximumLines: 13)
        }
    }

    private var topicPlaceholder: String? {
        controller.isFreeChat
            ? "What should they talk about?"
            : controller.selectedTemplate?.topicPrompt
    }

    /// Writes go through the controller, which is where typing-begins-a-
    /// steer lives; a plain binding would leave that transition to the view.
    private var steeringBinding: Binding<String> {
        Binding(get: { controller.steeringText },
                set: { controller.setSteeringText($0) })
    }
}

/// The foot of the card: the run options leading — the end condition and
/// tiling, each its own control (a hint line takes their place mid-run) —
/// and the one primary circle trailing. Ending a run lives in the title
/// strip's overflow menu (PerchChrome), per the converged proposal — Pause
/// is the safety action, so it keeps the only big button.
private struct PerchComposerToolbar: View {
    @Bindable var controller: RelayController
    /// Bumped whenever the turn count should take the keyboard: when the
    /// limit is switched on, and when its label is clicked.
    @State private var turnsFocus = 0
    /// The chips' height, and the square a bare glyph sits in.
    private static let chipSize = Perch.s(32)

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            if controller.isRunning {
                Text(controller.isSteering
                     ? "Esc clears the note"
                     : "Type a note and we'll pause so you can finish it")
                    .font(Perch.text(11))
                    .foregroundColor(Perch.placeholder)
                    .contentTransition(.opacity)
                    .animation(Perch.fade, value: controller.isSteering)
            } else {
                HStack(spacing: Perch.s(6)) {
                    turnLimitChip
                    tileChip
                }
            }
            Spacer(minLength: Perch.s(8))
            primaryButton
        }
    }

    // MARK: Run options

    /// Both options draw the way the chat apps' tool toggles do: nothing at
    /// rest but the glyph, the wash under the pointer, and once on, the
    /// quiet amber capsule grown around a label that reads the setting out.
    /// Amber is the panel's word for "live", and an option that will shape
    /// the run is live. The glyph keeps its place through the change — the
    /// capsule grows past it, so the eye stays where it clicked. The chips
    /// are a size under the primary circle, with air around the glyph, so
    /// they read as buttons of the same family rather than as its footnotes.
    private func chip<Content: View>(on: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .foregroundColor(on ? Perch.amberText : Perch.secondary)
            .frame(height: Self.chipSize)
            .background(Capsule().fill(Perch.amberBack).opacity(on ? 1 : 0))
            .perchHover(Capsule(), tint: on ? Perch.amber : Perch.ink,
                        opacity: on ? 0.08 : 0.06)
    }

    /// A chip's glyph. One whose symbol stays put bounces to mark the
    /// press; one whose symbol changes with the state — `swaps` — replaces
    /// itself instead, the system's own swap, rather than popping twice.
    private func glyph(_ symbol: String, on: Bool, swaps: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Perch.s(13), weight: .medium))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: !swaps && on)
            .frame(width: Self.chipSize, height: Self.chipSize)
            .padding(.leading, on ? Perch.s(3) : 0)
    }

    /// The label a chip grows: out of the glyph's side, scaling up as the
    /// capsule stretches to make room for it.
    private var labelTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.5, anchor: .leading))
    }

    /// Tiling: one press, one word.
    private var tileChip: some View {
        Button {
            withAnimation(Perch.spring) { controller.tileWindows.toggle() }
        } label: {
            chip(on: controller.tileWindows) {
                // A window as it is when off; the split when the run will
                // arrange two. (Two windows one behind another is the copy
                // glyph — it read as duplicate, not as untiled.)
                glyph(controller.tileWindows ? "rectangle.split.2x1" : "macwindow",
                      on: controller.tileWindows, swaps: true)
                if controller.tileWindows {
                    Text("Tile")
                        .font(Perch.text(12, .medium))
                        .fixedSize()
                        .padding(.trailing, Perch.s(12))
                        .transition(labelTransition)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(controller.tileWindows
              ? "Tiling on: ChatGPT left, Claude right when the run starts. Click to leave the windows where they are."
              : "Tile the chat windows — ChatGPT left, Claude right — when the run starts")
    }

    /// The end condition: the checkered flag is the switch, and the label it
    /// grows is the value itself. Switching it on hands the keyboard to the
    /// count with its digits selected, so the whole gesture is click, type a
    /// number, Return — and the arrows or the scroll wheel nudge it without
    /// a stepper in sight.
    private var turnLimitChip: some View {
        chip(on: controller.limitTurns) {
            Button {
                withAnimation(Perch.spring) { controller.limitTurns.toggle() }
                if controller.limitTurns { turnsFocus += 1 }
            } label: {
                glyph("flag.checkered", on: controller.limitTurns)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(controller.limitTurns
                  ? "Ending after the set number of turns. Click to end only when both agents sign off."
                  : "End condition: stop after a set number of turns. Off, the run ends when both agents sign off (or on an empty reply, a timeout, or End session).")
            if controller.limitTurns {
                turnCount.transition(labelTransition)
            }
        }
    }

    /// The count and its unit. The unit is a click into the number, so the
    /// whole label edits: the number is the value, the glyph is the switch.
    private var turnCount: some View {
        HStack(spacing: Perch.s(3)) {
            PerchTurnsField(value: $controller.turns,
                            font: .monospacedDigitSystemFont(ofSize: Perch.s(12),
                                                             weight: .medium),
                            color: Perch.amberTextNS,
                            focusRequest: turnsFocus)
            Button {
                turnsFocus += 1
            } label: {
                Text(controller.turns == 1 ? "turn" : "turns")
                    .font(Perch.text(12, .medium))
                    .fixedSize()
                    .padding(.trailing, Perch.s(12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .help("How many turns to allow. Type a number, or nudge it with ↑ ↓ or the scroll wheel.")
    }

    // MARK: The primary button

    /// One filled circle, morphing with the state the way the chat apps'
    /// own send button does: Run idle, Pause in a run, Send while a note is
    /// written, Resume while the pause holds. The amber is the panel's one
    /// accent, and this is where it lives.
    private var primaryButton: some View {
        let role = primaryRole
        return Button(action: role.action) {
            Image(systemName: role.icon)
                .font(.system(size: Perch.s(13), weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(.white)
                .frame(width: Perch.primaryDiameter, height: Perch.primaryDiameter)
                .background(Circle().fill(Perch.amber))
                .perchHover(Circle(), opacity: 0.1)
                .opacity(role.disabled ? 0.4 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(role.disabled)
        .keyboardShortcut(controller.isRunning ? nil : .defaultAction)
        .help(role.help)
        .animation(.easeInOut(duration: 0.15), value: role.icon)
    }

    private struct PrimaryRole {
        let icon: String
        let help: String
        let disabled: Bool
        let action: () -> Void
    }

    private var primaryRole: PrimaryRole {
        guard controller.isRunning else {
            return PrimaryRole(icon: "play.fill",
                               help: "Start the relay",
                               disabled: !controller.instructionsReady,
                               action: { controller.start() })
        }
        if controller.isSteering {
            return PrimaryRole(icon: "arrow.up",
                               help: "Send your note with the next message",
                               disabled: false,
                               action: { controller.sendSteering() })
        }
        if controller.isPaused {
            return PrimaryRole(icon: "play.fill",
                               help: controller.isHolding
                                   ? "Send the held reply and continue"
                                   : "Call off the pause and let the run carry on",
                               disabled: false,
                               action: { controller.togglePause() })
        }
        return PrimaryRole(icon: "pause.fill",
                           help: "Hold the run at the next handoff",
                           disabled: false,
                           action: { controller.togglePause() })
    }
}

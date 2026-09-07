// The composer: one card whose first two lines are the conversation's setup
// — the shape tabs and the selected shape's instructions — closed off by a
// hairline, with the person's own words below the line and the actions at
// the foot. The arrangement is the converged proposal
// (docs/design-proposals/chat-composer/converged-composer.html): the shape
// choice is input, so it lives on the composing surface, and the card keeps
// its anatomy across states — in a run the setup zone folds into a one-line
// context row above the same hairline, and the editor becomes the steering
// field. That field is closed while the agents work, with the one filled
// circle standing in the middle of it as Pause to steer; pressing it holds
// the run at the next handoff, springs the circle down to the foot's
// corner, and opens the field. Return sends the note and closes the field
// again, the note waiting under a blur for its handoff. Where the note is,
// and what became of it, is the head's line to say (PerchSteering). The
// foot follows the chat apps' own composers: the run options are bare
// glyphs that grow a label when they are on, and one filled circle is the
// primary action. See PerchPanelView for the panel.

import SwiftUI

/// The card: structure only. The zone, the editor, and the toolbar are
/// their own observation scopes so a keystroke invalidates the text and the
/// button that watches it, never the tabs or the perches above.
struct PerchComposer: View {
    let controller: RelayController
    /// The primary circle's coordinate space. Wherever the circle stands —
    /// the foot's corner idle and while the field is open, the middle of
    /// the field while it is closed — it is a source in this space under one
    /// id, so a change of state moves it rather than swapping it.
    @Namespace private var primarySpace

    var body: some View {
        // The primary circle is Liquid Glass (PerchPrimaryFace), and glass
        // morphs between two placements only inside one container — so the
        // card is that container, with the editor's slot and the foot's
        // corner both in it.
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: Perch.cardGap) {
                PerchConfigZone(controller: controller)
                PerchComposerEditor(controller: controller, primarySpace: primarySpace)
                PerchComposerToolbar(controller: controller, primarySpace: primarySpace)
            }
        }
        .padding(Perch.boxInset)
        .animation(Perch.spring, value: controller.isSteering)
        .background(RoundedRectangle(cornerRadius: Perch.boxCorner).fill(Perch.well))
    }
}

/// The setup zone above the hairline: idle, the shape tabs and — for any
/// shape but Free chat — the instruction preview; in a run, the one-line
/// context row. The hairline itself is drawn here so the zone and its rule
/// always move together.
private struct PerchConfigZone: View {
    let controller: RelayController
    /// The tab thumb's coordinate space: every tab is a source in it, and
    /// the thumb follows whichever one the selection names.
    @Namespace private var tabSpace

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.cardGap) {
            if controller.isRunning {
                contextLine
                    .frame(height: Perch.s(20), alignment: .leading)
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
        if controller.windowsTiled { parts.append("Tiled") }
        return parts.joined(separator: " · ")
    }
}

/// The editor in its three modes: topic (Free chat included), full prompt,
/// steering field. Its own scope so typing invalidates only this view and
/// the toolbar's morphing button.
private struct PerchComposerEditor: View {
    @Bindable var controller: RelayController
    let primarySpace: Namespace.ID

    private static let steeringFont = NSFont.systemFont(ofSize: Perch.s(12.5))

    /// The field's height floor in a run: the editor's two lines, or the
    /// circle that stands in the closed field, whichever is taller, so
    /// opening and closing the field moves no edge of the card.
    private static let steeringMinimumHeight = max(
        GrowingTextEditor.height(lines: 2, font: steeringFont), Perch.primaryDiameter)

    var body: some View {
        if controller.isRunning {
            if controller.isSteering {
                steeringField
                    .transition(.opacity)
            } else {
                steeringRest
                    .transition(.opacity)
            }
        } else if !controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.topic,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 3, maximumLines: 12,
                              // Free chat shows no preview, so the editor
                              // holds the preview zone's height itself and
                              // the card is one size for every shape.
                              extraMinimumHeight: controller.isFreeChat
                                  ? Perch.previewZoneHeight : 0,
                              onSubmit: { withAnimation(Perch.spring) { controller.start() } })
        } else {
            // Prose mode: Return breaks the line, as a prompt editor should;
            // Run is the button's job here. The same three lines as the
            // topic field, so switching to Custom moves no edge of the card.
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 3, maximumLines: 13)
        }
    }

    private var topicPlaceholder: String? {
        controller.isFreeChat
            ? "What should they talk about?"
            : controller.selectedTemplate?.topicPrompt
    }

    // MARK: The steering field

    /// The field, open: the run holds at the next handoff while it is, and
    /// the next thing typed lands here. Return sends the note and closes
    /// the field; Esc empties it, and Esc on an empty field closes it and
    /// continues without a note.
    private var steeringField: some View {
        GrowingTextEditor(text: steeringBinding,
                          font: Self.steeringFont,
                          textColor: Perch.inkNS,
                          placeholderColor: Perch.placeholderNS,
                          placeholder: controller.steeringText.isEmpty
                              ? "A note for the next handoff…" : nil,
                          minimumLines: 2, maximumLines: 8,
                          extraMinimumHeight: Self.steeringMinimumHeight
                              - GrowingTextEditor.height(lines: 2, font: Self.steeringFont),
                          takesFocusOnAppear: true,
                          onSubmit: { withAnimation(Perch.spring) { controller.sendSteering() } },
                          onEscape: { _ in withAnimation(Perch.spring) { controller.escapeSteering() } },
                          session: controller.steeringEditor)
            .help(controller.steeringHasText
                  ? "Return sends the note with the next handoff and lets the run go on; Esc clears it."
                  : "The run holds at the next handoff while the field is open. Write a note and press Return, or Esc to continue without one.")
    }

    /// The field, closed: no typing, the circle in the middle as Pause to
    /// steer, and the queued note — when there is one — under a blur behind
    /// it, there to be seen but not touched until the circle pulls it back
    /// as Pause to edit. The whole area is the circle's target, so a click
    /// on the blurred words does what the button does.
    private var steeringRest: some View {
        Text(controller.steeringText)
            .font(Font(Self.steeringFont as CTFont))
            .foregroundColor(Perch.ink)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .padding(.vertical, GrowingTextEditor.insetHeight)
            .frame(maxWidth: .infinity, minHeight: Self.steeringMinimumHeight,
                   alignment: .topLeading)
            .blur(radius: Perch.s(2.5))
            .opacity(controller.steeringQueued ? 0.75 : 0)
            .accessibilityHidden(true)
            .overlay { pauseToSteer }
            .contentShape(Rectangle())
            .onTapGesture { begin() }
            .animation(Perch.fade, value: controller.steeringQueued)
    }

    /// The circle where the words would be. Its word says what the press
    /// opens the field with: nothing, or the queued note.
    private var pauseToSteer: some View {
        Button(action: begin) {
            PerchPrimaryFace(icon: "pause.fill",
                             word: controller.isSteeringPending ? "Pausing…"
                                : controller.steeringQueued ? "Pause to edit" : "Pause to steer",
                             space: primarySpace)
        }
        .buttonStyle(.plain)
        .disabled(controller.isSteeringPending)
        .opacity(controller.isSteeringPending ? 0.55 : 1)
        .help(controller.steeringQueued
              ? "Hold the run at the next handoff and bring the queued note back into the field"
              : "Hold the run at the next handoff and open the field for a note")
        .accessibilityLabel(controller.isSteeringPending ? "Pausing"
                            : controller.steeringQueued ? "Pause to edit the note" : "Pause to steer")
    }

    /// The press springs the circle to the corner, so the state change is
    /// animated from here rather than in the controller.
    private func begin() {
        withAnimation(Perch.spring) { controller.beginSteering() }
    }

    /// Writes go through the controller, which takes text only while the
    /// field is open.
    private var steeringBinding: Binding<String> {
        Binding(get: { controller.steeringText },
                set: { controller.setSteeringText($0) })
    }
}

/// The one filled circle's face, wherever it stands: the glyph in a circle
/// of primaryDiameter and, when the role has a word, the word after it with
/// the capsule grown around both. Every placement is a source in the
/// composer's primary space under one id, so when the role moves — into the
/// middle of the field as Pause to steer, back to the corner as Continue —
/// the capsule travels and reshapes rather than appearing anew, and a word
/// that leaves in place (Continue's, as words arrive in the field) scales
/// out of the glyph's side the way the option chips' labels do. Clipped to
/// itself so the word does not spill while the capsule closes to a circle.
/// The theme's accent stays with the primary action, as the tint of its
/// Liquid Glass: the capsule is glass over the card, not a filled shape.
private struct PerchPrimaryFace: View {
    let icon: String
    var word: String? = nil
    var dimmed = false
    let space: Namespace.ID

    private static let id = "primary"

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: Perch.s(13), weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Perch.primaryDiameter, height: Perch.primaryDiameter)
            if let word {
                Text(word)
                    .font(Perch.text(12, .semibold))
                    .fixedSize()
                    .padding(.trailing, Perch.s(14))
                    .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .leading)))
            }
        }
        .foregroundColor(Perch.onAccent)
        // Liquid Glass in the theme's accent, interactive so the system
        // answers the pointer and the press itself; the panel's own hover
        // wash is left off, or the two would stack.
        .glassEffect(.regular.tint(Perch.accent).interactive(), in: Capsule())
        .clipShape(Capsule())
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Capsule())
        // The glass morphs between the field and the corner under the same
        // id the geometry matches on, so the material travels with the
        // capsule instead of fading out and in.
        .glassEffectID(Self.id, in: space)
        .matchedGeometryEffect(id: Self.id, in: space)
    }
}

/// The foot of the card: the run options leading — the end condition and
/// tiling, each its own control (a hint line, or Clear note, takes their
/// place mid-run) — and the one primary circle trailing, when it is here.
/// Ending a run lives in the title strip's overflow menu (PerchChrome), per
/// the converged proposal — the circle is the safety action, so it stays
/// the only big button.
private struct PerchComposerToolbar: View {
    @Bindable var controller: RelayController
    let primarySpace: Namespace.ID
    /// Bumped whenever the turn count should take the keyboard: when the
    /// limit is switched on, and when its label is clicked.
    @State private var turnsFocus = 0
    /// The chips' height, and the square a bare glyph sits in.
    private static let chipSize = Perch.s(32)

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            if controller.isRunning {
                runFoot
            } else {
                HStack(spacing: Perch.s(6)) {
                    turnLimitChip
                    tileChip
                }
            }
            Spacer(minLength: Perch.s(8))
            primaryButton
        }
        // The circle sets the foot's height; while it stands in the field
        // the foot keeps that height without it.
        .frame(minHeight: Perch.primaryDiameter)
    }

    // MARK: The foot mid-run

    /// The leading slot in a run: while the field is open, what the keys
    /// do; while a note is queued, the one explicit way to drop it without
    /// opening the field. Where the note is lives in the head.
    @ViewBuilder
    private var runFoot: some View {
        if controller.steeringQueued, !controller.isSteering {
            Button {
                withAnimation(Perch.fade) { _ = controller.clearSteering() }
            } label: {
                Text("Clear note")
                    .font(Perch.text(11, .medium))
                    .perchHoverInk(idle: Perch.secondary, active: Perch.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Drop the queued note — nothing goes with the next handoff")
            .transition(.opacity)
        } else {
            Text(footHint)
                .font(Perch.text(11))
                .foregroundColor(Perch.placeholder)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(Perch.fade, value: footHint)
                .transition(.opacity)
        }
    }

    private var footHint: String {
        guard controller.isSteering else { return "" }
        return controller.steeringHasText
            ? "Return sends it with the next handoff · Esc clears it"
            : "Write a note · Esc continues without one"
    }

    // MARK: Run options

    /// Both options draw the way the chat apps' tool toggles do: nothing at
    /// rest but the glyph, the wash under the pointer, and once on, the
    /// quiet accent capsule grown around a label that reads the setting out.
    /// The accent is the panel's word for "live", and an option that will shape
    /// the run is live. The glyph keeps its place through the change — the
    /// capsule grows past it, so the eye stays where it clicked. The chips
    /// are a size under the primary circle, with air around the glyph, so
    /// they read as buttons of the same family rather than as its footnotes.
    private func chip<Content: View>(on: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .foregroundColor(on ? Perch.accentText : Perch.secondary)
            .frame(height: Self.chipSize)
            .background(Capsule().fill(Perch.accentBack).opacity(on ? 1 : 0))
            .perchHover(Capsule(), tint: on ? Perch.accent : Perch.ink,
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

    /// Tiling: one press, one word — and the windows move as it is
    /// pressed, not at Start. Offered once both apps read Ready, since the
    /// windows have to be there to tile (dimmed until then, the tooltip
    /// saying so); on, it can always be pressed again to put them back.
    private var tileChip: some View {
        let offered = controller.windowsTiled || controller.canTile
        return Button {
            withAnimation(Perch.spring) { controller.toggleTiling() }
        } label: {
            chip(on: controller.windowsTiled) {
                // A window as it is when off; the split once two stand
                // arranged. (Two windows one behind another is the copy
                // glyph — it read as duplicate, not as untiled.)
                glyph(controller.windowsTiled ? "rectangle.split.2x1" : "macwindow",
                      on: controller.windowsTiled, swaps: true)
                if controller.windowsTiled {
                    Text("Tiled")
                        .font(Perch.text(12, .medium))
                        .fixedSize()
                        .padding(.trailing, Perch.s(12))
                        .transition(labelTransition)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(offered ? 1 : 0.4)
        .help(tileHelp)
    }

    private var tileHelp: String {
        if controller.windowsTiled {
            return "Tiled: ChatGPT left, Claude right. Click to put the windows back where they were."
        }
        return controller.canTile
            ? "Tile the chat windows now — ChatGPT left, Claude right"
            : "Tile the chat windows — once both apps read Ready"
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
                            color: Perch.accentTextNS,
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

    /// The one filled circle at the foot's corner: Run idle, and in a run
    /// only while the field is open — a capsule reading Continue while the
    /// field is empty, since a bare play glyph there did not say whether it
    /// went on with nothing or was waiting for words, closing to the arrow
    /// circle once there are words to send. The word leaves exactly when
    /// the button stops meaning "go on without a note". While the field is
    /// closed the circle stands in the middle of it as Pause to steer
    /// (PerchComposerEditor); the press springs it down here, and sending
    /// springs it back. Run springs it up into the field the same way when
    /// the run starts.
    @ViewBuilder
    private var primaryButton: some View {
        if let role = primaryRole {
            Button(action: role.action) {
                PerchPrimaryFace(icon: role.icon, word: role.word, dimmed: role.disabled,
                                 space: primarySpace)
            }
            .buttonStyle(.plain)
            .disabled(role.disabled)
            .keyboardShortcut(controller.isRunning ? nil : .defaultAction)
            .help(role.help)
            .accessibilityLabel(role.label)
            .animation(.easeInOut(duration: 0.15), value: role.icon)
            .animation(Perch.spring, value: role.word)
            .transition(.opacity)
        }
    }

    private struct PrimaryRole {
        let icon: String
        /// The accessible name — what the circle is, said in a word or two.
        let label: String
        /// The word the capsule carries after the glyph, for the role whose
        /// glyph does not say enough on its own.
        var word: String? = nil
        let help: String
        let disabled: Bool
        let action: () -> Void
    }

    /// nil while the circle stands in the field.
    private var primaryRole: PrimaryRole? {
        guard controller.isRunning else {
            return PrimaryRole(icon: "play.fill", label: "Run",
                               help: "Start the relay",
                               disabled: !controller.instructionsReady,
                               action: { withAnimation(Perch.spring) { controller.start() } })
        }
        guard controller.isSteering else { return nil }
        if controller.steeringHasText {
            return PrimaryRole(icon: "arrow.up", label: "Send",
                               help: "Send the note with the next handoff and let the run go on",
                               disabled: false,
                               action: { withAnimation(Perch.spring) { controller.sendSteering() } })
        }
        return PrimaryRole(icon: "play.fill", label: "Continue", word: "Continue",
                           help: controller.isHolding
                               ? "Send the held reply and go on, without a note"
                               : "Call off the pause and let the run carry on, without a note",
                           disabled: false,
                           action: { withAnimation(Perch.spring) { controller.sendSteering() } })
    }
}

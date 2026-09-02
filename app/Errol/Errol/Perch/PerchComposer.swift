// The composer: one card whose first two lines are the conversation's setup
// — the quick shape pills and the selected shape's instructions — closed
// off by a hairline, with the person's own words below the line and the
// actions at the foot. The arrangement is the converged proposal
// (docs/design-proposals/chat-composer/converged-composer.html): the pills
// are input, so they live on the composing surface, and the card keeps its
// anatomy across states — in a run the setup zone folds into a one-line
// context row above the same hairline, and the editor becomes the steering
// field (typing is what begins a steer, RelayController.setSteeringText).
// See PerchPanelView for the skin.

import SwiftUI

/// The card: structure only. The zone, the editor, and the toolbar are
/// their own observation scopes so a keystroke invalidates the text and the
/// button that watches it, never the pills or the perches above.
struct PerchComposer: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            PerchConfigZone(controller: controller)
            PerchComposerEditor(controller: controller)
            PerchComposerToolbar(controller: controller)
        }
        .padding(Perch.s(13))
        .background(RoundedRectangle(cornerRadius: Perch.boxCorner).fill(Perch.well))
    }
}

/// The setup zone above the hairline: idle, the quick pills and the
/// instruction preview; in a run, the one-line context row (or the amber
/// hold notice while a steer is being written). The hairline itself is
/// drawn here so the zone and its rule always move together.
private struct PerchConfigZone: View {
    let controller: RelayController
    /// Whether the preview band shows the whole instruction set rather than
    /// its first two lines. Presentation state, so it lives with the view.
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
            if controller.isRunning {
                if controller.isSteering {
                    holdNotice
                } else {
                    contextLine
                }
            } else {
                pillRow
                previewRow
            }
            Rectangle()
                .fill(Perch.hairline)
                .frame(height: 1)
        }
    }

    // MARK: The quick pills

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

    private var pillRow: some View {
        HStack(spacing: Perch.s(6)) {
            pill(name: RelayController.freeConversation,
                 icon: "circle.dashed",
                 selected: controller.isFreeChat)
            ForEach(quickTemplates) { template in
                pill(name: template.name,
                     icon: WireShapeIcons.icon(for: template.name),
                     selected: controller.conversation == template.name)
            }
            morePill
        }
    }

    private func pill(name: String, icon: String, selected: Bool) -> some View {
        Button {
            controller.selectConversation(name)
        } label: {
            pillLabel(text: name, icon: icon, selected: selected)
        }
        .buttonStyle(.plain)
        .help(name == RelayController.freeConversation
              ? "Open conversation — the topic is the whole opening message"
              : "Open with the \(name) instructions")
    }

    private func pillLabel(text: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: Perch.s(5)) {
            Image(systemName: icon)
                .font(.system(size: Perch.s(10), weight: .medium))
            Text(text)
                .font(Perch.text(12, .medium))
                .lineLimit(1)
        }
        .foregroundColor(selected ? Perch.paper : Perch.secondary)
        .padding(.horizontal, Perch.s(11))
        .frame(height: Perch.s(25))
        .background(Capsule().fill(selected ? Perch.ink : Perch.paper))
        .overlay(Capsule().stroke(selected ? Perch.ink : Perch.chipEdge, lineWidth: 1))
        .perchHover(Capsule(), tint: selected ? .white : Perch.ink,
                    opacity: selected ? 0.14 : 0.06)
        .contentShape(Capsule())
    }

    /// More owns everything the row does not: the remaining shapes, writing
    /// from scratch, and the way into Settings. A shape chosen here takes
    /// over the pill's label, so the current selection is always visible
    /// without the row allocating space to every possible shape.
    private var morePill: some View {
        Menu {
            ForEach(overflowTemplates) { template in
                Button {
                    controller.selectConversation(template.name)
                } label: {
                    Label(template.name,
                          systemImage: WireShapeIcons.icon(for: template.name))
                }
            }
            Button {
                controller.selectConversation(RelayController.customConversation)
            } label: {
                Label("Write from scratch", systemImage: WireShapeIcons.customIcon)
            }
            Divider()
            Button("Manage shapes…") { controller.openSettings() }
        } label: {
            pillLabel(text: moreHoldsSelection ? controller.conversation : "More",
                      icon: moreHoldsSelection
                          ? WireShapeIcons.icon(for: controller.conversation)
                          : "ellipsis",
                      selected: moreHoldsSelection)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("The other shapes, a from-scratch prompt, and the shape editor")
    }

    // MARK: The instruction preview

    /// Under the pills, what the selected shape will actually say: the
    /// template's instructions in a quiet mono band, two lines until asked
    /// for all of them, with a pencil for a session-only edit. While that
    /// edit is open the band gives way to the way back out of it.
    @ViewBuilder
    private var previewRow: some View {
        if controller.isEditingInstructions, controller.selectedTemplate != nil {
            HStack(spacing: Perch.s(8)) {
                Text("Editing the full opening message below")
                    .font(Perch.text(11))
                    .foregroundColor(Perch.muted)
                Spacer(minLength: Perch.s(6))
                Button("Back to simple setup") {
                    controller.resetInstructionsToTemplate()
                }
                .buttonStyle(.plain)
                .font(Perch.text(11, .medium))
                .perchHoverInk()
                .help("Discard this session's edits and return to the \(controller.conversation) topic field")
            }
            .padding(.horizontal, Perch.s(2))
        } else if controller.selectedTemplate == nil, !controller.isFreeChat {
            Text("Writing the opening message from scratch")
                .font(Perch.text(11))
                .foregroundColor(Perch.muted)
                .padding(.horizontal, Perch.s(2))
        } else {
            previewBand
        }
    }

    private var previewBand: some View {
        HStack(alignment: .top, spacing: Perch.s(8)) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Text(previewText)
                    .font(Perch.mono(10.5))
                    .foregroundColor(Perch.bandText)
                    .lineSpacing(Perch.s(2))
                    .lineLimit(expanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse the instructions"
                           : "Show the complete instructions")
            if !controller.isFreeChat {
                Button {
                    controller.editInstructions()
                } label: {
                    Image(systemName: WireShapeIcons.customIcon)
                        .font(.system(size: Perch.s(10), weight: .medium))
                        .foregroundColor(Perch.muted)
                        .frame(width: Perch.s(20), height: Perch.s(20))
                        .contentShape(Rectangle())
                        .perchHover(RoundedRectangle(cornerRadius: Perch.s(5)))
                }
                .buttonStyle(.plain)
                .help("Customize these instructions for this session only")
            }
        }
        .padding(Perch.s(9))
        .background(RoundedRectangle(cornerRadius: Perch.bandCorner).fill(Perch.band))
        // The band is one clickable surface (click to expand), so the whole
        // band answers the pointer; the pencil layers its own square on top.
        .perchHover(RoundedRectangle(cornerRadius: Perch.bandCorner))
    }

    private var previewText: String {
        if controller.isFreeChat {
            return "Open conversation — no preset structure; the topic below is the whole opening message."
        }
        return controller.selectedTemplate?.body ?? ""
    }

    // MARK: The zone mid-run

    /// The setup zone folded to one line: the loaded shape and the run
    /// options, readable but no longer controls — a run owns them.
    private var contextLine: some View {
        HStack(spacing: Perch.s(6)) {
            Image(systemName: controller.isFreeChat
                  ? "circle.dashed"
                  : WireShapeIcons.icon(for: controller.conversation))
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

    /// While a steer is being written the zone carries the hold, in the
    /// precise voice: what the run is doing about the note, not just that
    /// it is paused.
    private var holdNotice: some View {
        Text(controller.isHolding
             ? "Paused at the handoff — the note rides the delivery when you resume."
             : "Holding at the next handoff — the note rides it to whoever replies next.")
            .font(Perch.text(11))
            .foregroundColor(Perch.amberText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Perch.s(9))
            .background(RoundedRectangle(cornerRadius: Perch.bandCorner).fill(Perch.amberBack))
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
                .help("Steer the conversation: typing pauses at the next handoff; Return sends the note, Esc clears it")
        } else if !controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.topic,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 3, maximumLines: 12,
                              onSubmit: { controller.start() })
        } else {
            // Prose mode: Return breaks the line, as a prompt editor should;
            // Run is the button's job here.
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Perch.s(12.5)),
                              textColor: Perch.inkNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 4, maximumLines: 13)
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

/// The foot of the card: the options chip leading (a hint line mid-run),
/// the one primary circle trailing. Ending a run lives in the title
/// strip's overflow menu (PerchChrome), per the converged proposal — Pause
/// is the safety action, so it keeps the only big button.
private struct PerchComposerToolbar: View {
    let controller: RelayController
    @State private var optionsOpen = false

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            if controller.isRunning {
                Text(controller.isSteering
                     ? "Esc clears the note"
                     : "Typing pauses at the next handoff")
                    .font(Perch.text(11))
                    .foregroundColor(Perch.placeholder)
            } else {
                optionsChip
            }
            Spacer(minLength: Perch.s(8))
            primaryButton
        }
    }

    // MARK: Run options

    /// The turn limit and tiling, behind one chip that always reads out its
    /// setting — "Auto" is a state worth a word, not an empty chip.
    private var optionsChip: some View {
        Button {
            optionsOpen.toggle()
        } label: {
            HStack(spacing: Perch.s(5)) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: Perch.s(10), weight: .medium))
                Text(optionsSummary)
                    .font(Perch.text(12, .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: Perch.s(7), weight: .semibold))
                    .foregroundColor(Perch.muted)
            }
            .foregroundColor(Perch.secondary)
            .padding(.horizontal, Perch.s(11))
            .frame(height: Perch.s(25))
            .background(Capsule().fill(Perch.paper))
            .overlay(Capsule().stroke(Perch.chipEdge, lineWidth: 1))
            .perchHover(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Run options: the turn limit and window tiling")
        // Anchored to a fixed span at the chip's leading end rather than the
        // chip's bounds: the label re-reads the setting as it changes
        // ("Auto" to "10 turns"), so a bounds anchor would slide the open
        // popover with every edit made inside it. The chip's leading edge
        // never moves.
        .popover(isPresented: $optionsOpen,
                 attachmentAnchor: .rect(.rect(CGRect(x: 0, y: 0,
                                                      width: Perch.s(44),
                                                      height: Perch.s(25)))),
                 arrowEdge: .bottom) {
            PerchRunOptions(controller: controller)
        }
    }

    private var optionsSummary: String {
        var parts = [controller.limitTurns ? "\(controller.turns) turns" : "Auto"]
        if controller.tileWindows { parts.append("Tile") }
        return parts.joined(separator: " · ")
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
                .foregroundColor(.white)
                .frame(width: Perch.s(36), height: Perch.s(36))
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
                               help: "Send the note; it reaches whoever replies next, and the other side a turn later",
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

/// The popover behind the options chip: native controls on the panel's own
/// paper.
private struct PerchRunOptions: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(10)) {
            HStack(spacing: Perch.s(8)) {
                Toggle("Limit turns", isOn: $controller.limitTurns)
                    .toggleStyle(.checkbox)
                    .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or End session). On: also stop after this many responses.")
                HStack(spacing: Perch.s(3)) {
                    TextField("10", value: $controller.turns, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: Perch.s(40))
                    Stepper("", value: $controller.turns, in: 1...99)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .disabled(!controller.limitTurns)
                .opacity(controller.limitTurns ? 1 : 0.45)
            }
            Toggle("Tile the chat windows", isOn: $controller.tileWindows)
                .toggleStyle(.checkbox)
                .help("Arrange ChatGPT left, Claude right when the run starts")
        }
        .font(Perch.text(12))
        .padding(Perch.s(14))
        .background(Perch.paper)
        .environment(\.colorScheme, .light)
    }
}

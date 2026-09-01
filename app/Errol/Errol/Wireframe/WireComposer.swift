// The composer: the one card under the instrument head, holding everything
// the old console spread over four rows — the shape picker, the topic or
// full-prompt editor, the run options, and the run controls. It borrows the
// chat apps' own idiom (a roomy input with its controls riding inside it,
// one round primary button that morphs with the state) but keeps the
// wireframe's grays and mono labels, so it reads as this instrument's
// composer rather than a transplant. See WireframePanelView for the skin.
//
// The card is the same object in every state; only its contents turn over.
// Idle, the editor holds the topic (or the full prompt) and the toolbar
// carries the shape chip, the options chip, and RUN. In a run the editor
// becomes the steering field — typing is what begins a steer, holding the
// run at the next handoff (RelayController.setSteeringText) — and the
// toolbar carries the loaded shape as a passive chip, END, and the primary
// button, now PAUSE, RESUME, or SEND depending on the pause and the note.

import SwiftUI

/// The card: structure only. It reads isRunning and isSteering for the
/// border; the editor and toolbar are their own observation scopes so a
/// keystroke invalidates the text and the button that watches it, never
/// the chips or the instruments above.
struct WireComposer: View {
    let controller: RelayController

    var body: some View {
        VStack(spacing: Wire.s(6)) {
            WireComposerEditor(controller: controller)
            WireComposerToolbar(controller: controller)
        }
        .padding(Wire.s(10))
        .background(RoundedRectangle(cornerRadius: Wire.boxCorner).fill(Wire.well))
        .overlay(
            // The border firms up while a steer is being written: the card
            // is holding a message for the conversation, which is the same
            // thing the working side's card does, said more quietly.
            RoundedRectangle(cornerRadius: Wire.boxCorner)
                .stroke(controller.isSteering ? Wire.ink.opacity(0.6)
                                              : Wire.faint.opacity(0.5),
                        lineWidth: Wire.s(1))
        )
    }
}

/// The editor in its three modes: topic, full prompt, steering note. Its
/// own scope so typing invalidates only this view (plus whatever reads the
/// text — the primary button's morph is deliberate).
private struct WireComposerEditor: View {
    @Bindable var controller: RelayController

    var body: some View {
        if controller.isRunning {
            GrowingTextEditor(text: steeringBinding,
                              font: .systemFont(ofSize: Wire.s(11)),
                              textColor: NSColor(calibratedWhite: 0.20, alpha: 1),
                              placeholder: steeringPlaceholder,
                              minimumLines: 2, maximumLines: 8,
                              onSubmit: { controller.sendSteering() },
                              onEscape: { controller.cancelSteer() })
                .help("Steer the conversation: typing holds the run at the next handoff; Return posts the note, Esc calls it off")
        } else if !controller.showsFullInstructionsEditor,
                  let template = controller.selectedTemplate {
            GrowingTextEditor(text: $controller.topic,
                              font: .systemFont(ofSize: Wire.s(11)),
                              textColor: NSColor(calibratedWhite: 0.20, alpha: 1),
                              placeholder: controller.topic.isEmpty
                                  ? template.topicPrompt : nil,
                              minimumLines: 3, maximumLines: 13,
                              onSubmit: { controller.start() })
        } else {
            // Prose mode: Return breaks the line, as a prompt editor should;
            // RUN is the button's job here.
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Wire.s(11)),
                              textColor: NSColor(calibratedWhite: 0.20, alpha: 1),
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 3, maximumLines: 13)
                .help(controller.selectedTemplate == nil
                      ? "Write the complete opening prompt"
                      : "Editing the complete \(controller.conversation) prompt; choosing another shape keeps this editor open")
        }
    }

    /// Writes go through the controller, which is where typing-begins-a-
    /// steer lives; a plain binding would leave that transition to the view.
    private var steeringBinding: Binding<String> {
        Binding(get: { controller.steeringText },
                set: { controller.setSteeringText($0) })
    }

    /// The placeholder teaches the contract once per glance: the first
    /// keystroke pauses the run. It only draws while the note is empty.
    private var steeringPlaceholder: String? {
        controller.steeringText.isEmpty
            ? "Steer the conversation — typing holds the run at the next handoff…"
            : nil
    }
}

/// The toolbar row inside the card: chips leading, the primary button
/// trailing, END beside it during a run.
private struct WireComposerToolbar: View {
    let controller: RelayController
    @State private var optionsOpen = false

    var body: some View {
        HStack(spacing: Wire.s(8)) {
            if controller.isRunning {
                loadedShapeChip
                Spacer(minLength: Wire.s(8))
                endButton
            } else {
                shapeChip
                optionsChip
                Spacer(minLength: Wire.s(8))
            }
            primaryButton
        }
    }

    // MARK: The shape chip and its menu

    private var shapeChip: some View {
        Menu {
            ForEach(conversationTemplates) { template in
                Button {
                    controller.selectConversation(template.name)
                } label: {
                    Label(template.name, systemImage: WireShapeIcons.icon(for: template.name))
                }
            }
            Button {
                controller.selectConversation(RelayController.customConversation)
            } label: {
                Label("Write from scratch", systemImage: WireShapeIcons.customIcon)
            }
            if controller.selectedTemplate != nil {
                Divider()
                if controller.isEditingInstructions {
                    Button("Back to simple setup") { controller.resetInstructionsToTemplate() }
                } else {
                    Button("Edit full prompt") { controller.editInstructions() }
                }
            }
            Divider()
            Button("Manage shapes…") { controller.openSettings() }
        } label: {
            chipLabel {
                Image(systemName: WireShapeIcons.icon(for: controller.conversation))
                    .font(.system(size: Wire.s(9), weight: .bold))
                Text(controller.conversation.uppercased())
                    .font(Wire.mono(8.5, .bold))
                // Full-prompt editing is a state of the shape, so the chip
                // wears its mark: the same pencil the menu offers it with.
                if controller.isEditingInstructions, controller.selectedTemplate != nil {
                    Image(systemName: WireShapeIcons.customIcon)
                        .font(.system(size: Wire.s(8), weight: .bold))
                        .foregroundColor(Wire.faint)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: Wire.s(7), weight: .bold))
                    .foregroundColor(Wire.faint)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(WireHandCursor(active: true))
        .help("Choose the conversation shape; the menu also opens the full prompt and the shape editor")
    }

    /// The loaded shape while a run owns it: the same chip gone passive —
    /// dashed, faint, uninterested in clicks — with the topic riding along
    /// so the head-down operator can still see what is running.
    private var loadedShapeChip: some View {
        HStack(spacing: Wire.s(4)) {
            Image(systemName: WireShapeIcons.icon(for: controller.conversation))
                .font(.system(size: Wire.s(9), weight: .bold))
            Text(controller.conversation.uppercased())
                .font(Wire.mono(8.5, .bold))
            Text(topicSummary)
                .font(Wire.text(9.5))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(Wire.faint)
        .padding(.horizontal, Wire.s(8))
        .frame(height: Wire.s(22))
        .overlay(
            Capsule().stroke(Wire.faint.opacity(0.5),
                             style: StrokeStyle(lineWidth: Wire.s(1),
                                                dash: [Wire.s(2.5), Wire.s(2.5)]))
        )
    }

    private var topicSummary: String {
        if controller.selectedTemplate == nil {
            return controller.customInstructions
                .components(separatedBy: .newlines).first ?? ""
        }
        return controller.topic
    }

    // MARK: The options chip and its popover

    /// Limit-turns and tiling used to be checkboxes in a row of their own;
    /// they are set-and-forget, so they live behind a chip now. The chip
    /// reads out whatever is switched on — an off-by-default option nobody
    /// can see is a trap — and opens the popover to change it.
    private var optionsChip: some View {
        Button {
            optionsOpen.toggle()
        } label: {
            chipLabel {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: Wire.s(9), weight: .bold))
                if let summary = optionsSummary {
                    Text(summary)
                        .font(Wire.mono(8.5, .bold))
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(WireHandCursor(active: true))
        .help("Run options: the turn limit and window tiling")
        .popover(isPresented: $optionsOpen, arrowEdge: .bottom) {
            WireRunOptions(controller: controller)
        }
    }

    private var optionsSummary: String? {
        var parts: [String] = []
        if controller.limitTurns { parts.append("\(controller.turns) TURNS") }
        if controller.tileWindows { parts.append("TILE") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The chips share one frame so a run option switching on cannot make
    /// the row's controls read as two different species.
    private func chipLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Wire.s(4), content: content)
            .foregroundColor(Wire.ink)
            .padding(.horizontal, Wire.s(8))
            .frame(height: Wire.s(22))
            .overlay(Capsule().stroke(Wire.ink.opacity(0.55), lineWidth: Wire.s(1)))
            .contentShape(Capsule())
    }

    // MARK: The buttons

    /// One primary button, morphing with the state the way the chat apps'
    /// own send button does: RUN idle, PAUSE in a run, SEND while a note is
    /// written, RESUME while the pause holds. The filled circle is the one
    /// solid element on the panel — the machine's main pushbutton.
    private var primaryButton: some View {
        let role = primaryRole
        return Button(action: role.action) {
            Image(systemName: role.icon)
                .font(.system(size: Wire.s(11), weight: .bold))
                .foregroundColor(role.disabled ? Wire.faint : Wire.paper)
                .frame(width: Wire.s(28), height: Wire.s(28))
                .background(Circle().fill(role.disabled ? Color.clear : Wire.ink))
                .overlay(Circle().stroke(role.disabled ? Wire.faint : Wire.ink,
                                         lineWidth: Wire.s(1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(role.disabled)
        .keyboardShortcut(controller.isRunning ? nil : .defaultAction)
        .modifier(WireHandCursor(active: !role.disabled))
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
                               help: "Post the note; it reaches whoever replies next, and the other side a turn later",
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

    /// Ending the run stays one click while it owns the machine — a hollow
    /// twin beside the primary button, never inside a menu.
    private var endButton: some View {
        Button {
            controller.stop()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: Wire.s(9), weight: .bold))
                .foregroundColor(Wire.ink)
                .frame(width: Wire.s(28), height: Wire.s(28))
                .overlay(Circle().stroke(Wire.ink, lineWidth: Wire.s(1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(WireHandCursor(active: true))
        .help("End the run at the next safe point")
    }
}

/// The popover behind the options chip: the two run options, in the
/// wireframe's own checkbox idiom on its own paper.
private struct WireRunOptions: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Wire.s(10)) {
            HStack(spacing: Wire.s(8)) {
                wireToggle("LIMIT TURNS", isOn: $controller.limitTurns)
                    .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or END). On: also stop after this many responses.")
                HStack(spacing: Wire.s(3)) {
                    TextField("10", value: $controller.turns, format: .number)
                        .textFieldStyle(.plain)
                        .font(Wire.mono(10))
                        .foregroundColor(Wire.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: Wire.s(26))
                        .padding(.vertical, Wire.s(2))
                        .background(Rectangle().fill(Wire.well))
                        .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                    Stepper("", value: $controller.turns, in: 1...99)
                        .labelsHidden()
                        .controlSize(.mini)
                }
                .disabled(!controller.limitTurns)
                .opacity(controller.limitTurns ? 1 : 0.45)
            }
            wireToggle("TILE THE CHAT WINDOWS", isOn: $controller.tileWindows)
                .help("Arrange ChatGPT left, Claude right when the run starts")
        }
        .padding(Wire.s(14))
        .background(Wire.paper)
        .environment(\.colorScheme, .light)
    }

    private func wireToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: Wire.s(5)) {
                ZStack {
                    Rectangle()
                        .stroke(Wire.ink, lineWidth: Wire.s(1))
                        .frame(width: Wire.s(10), height: Wire.s(10))
                    if isOn.wrappedValue {
                        Rectangle().fill(Wire.ink).frame(width: Wire.s(5), height: Wire.s(5))
                    }
                }
                Text(label)
                    .font(Wire.mono(8, .bold))
                    .foregroundColor(Wire.ink)
            }
            // A stroked Rectangle only hit-tests along its outline, so an
            // unticked box swallowed clicks aimed straight at it. The whole
            // row — box, gap, and label — is the target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The shipped shapes' glyphs, by name, with a fallback for shapes made in
/// Settings. A map rather than a per-shape setting on purpose: an icon
/// picker is a feature the settings card can grow if the fallback ever
/// grates.
enum WireShapeIcons {
    static let customIcon = "square.and.pencil"

    private static let known: [String: String] = [
        "Brainstorm": "lightbulb",
        "Debate": "bubble.left.and.bubble.right",
        "Code review": "chevron.left.forwardslash.chevron.right",
        "Adversary": "flag.2.crossed",
    ]

    static func icon(for name: String) -> String {
        if name == RelayController.customConversation { return customIcon }
        return known[name] ?? "text.bubble"
    }
}

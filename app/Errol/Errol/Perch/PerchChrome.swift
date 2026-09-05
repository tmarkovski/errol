// What the panel puts in the window's own title strip: the state pill and
// the session overflow menu, trailing. They are real toolbar items because
// the title bar claims the strip's clicks (MenuBarController.buildPanel has
// the account). See PerchPanelView for the panel.

import AppKit
import SwiftUI

final class PerchChromeToolbar: NSObject, NSToolbarDelegate {
    private static let status = NSToolbarItem.Identifier("perch-status")
    private static let overflow = NSToolbarItem.Identifier("perch-overflow")

    private let controller: RelayController

    init(controller: RelayController) {
        self.controller = controller
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "perch-chrome")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.status, Self.overflow]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = false
        switch id {
        case Self.status:
            item.view = FirstMouseHostingView(rootView: PerchStatePill(controller: controller))
        case Self.overflow:
            item.view = FirstMouseHostingView(rootView: PerchOverflowMenu(controller: controller))
        default:
            return nil
        }
        return item
    }
}

/// What the panel is doing, as a tinted pill: green when both sides are
/// relayable, amber while a run owns them, quiet otherwise. An indicator,
/// not a control — hit testing is off so a click on it drags the window.
struct PerchStatePill: View {
    let controller: RelayController

    var body: some View {
        let look = pillLook
        HStack(spacing: Perch.s(6)) {
            Circle()
                .fill(look.tint)
                .frame(width: Perch.s(6), height: Perch.s(6))
            Text(look.word)
                .font(Perch.text(11, .medium))
                .foregroundColor(look.tint)
        }
        .padding(.horizontal, Perch.s(10))
        .frame(height: Perch.s(21))
        .background(Capsule().fill(look.back))
        .allowsHitTesting(false)
    }

    private var pillLook: (word: String, tint: Color, back: Color) {
        if controller.isRunning {
            guard controller.holdRequested else {
                return ("Running", Perch.amberText, Perch.amberBack)
            }
            return (controller.isHolding ? "Paused" : "Pausing",
                    Perch.amberText, Perch.amberBack)
        }
        if controller.hasFinishedRun {
            return ("Done", Perch.green, Perch.greenBack)
        }
        if bothReady { return ("Both ready", Perch.green, Perch.greenBack) }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) {
            return ("Checking", Perch.muted, Perch.well)
        }
        return ("Waiting on apps", Perch.red, Perch.redBack)
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }
}

/// The session overflow: what the console offers but a run should not put a
/// big button under — ending the session foremost, per the converged
/// proposal, so Pause keeps the composer's only prominent control.
struct PerchOverflowMenu: View {
    let controller: RelayController

    var body: some View {
        Menu {
            Button("End session") { controller.stop() }
                .disabled(!controller.isRunning)
                .help("End the run at the next safe point")
            Divider()
            Button("Open transcript") { controller.openTranscript() }
            Button("Settings…") { controller.openSettings() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Perch.s(12), weight: .semibold))
                .foregroundColor(Perch.muted)
                .frame(width: Perch.s(22), height: Perch.s(22))
                .contentShape(Rectangle())
                .perchHover(RoundedRectangle(cornerRadius: Perch.s(6)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Session actions")
    }
}

// What the skin puts in the window's own title strip. See WireframePanelView
// for the skin.

import AppKit
import SwiftUI

/// The toolbar behind the title strip's contents: the state word and the
/// gear, trailing, in that order. (The wordmark stays a passive overlay on
/// the card — WireframePanelView — since a centered label needs no item.)
///
/// Real toolbar items rather than views laid over the strip, because the
/// title bar claims the strip's clicks: anything merely painted up here
/// would be pressing against a bar that answers first, which is why the
/// gear lived in a card row until the toolbar arrived. As items, the
/// toolbar hands them their clicks itself. The state word is deliberately
/// not an item that does anything — an indicator riding in the toolbar,
/// the established shape for status in a title strip — so it lets every
/// event through to the bar's drag.
final class WireChromeToolbar: NSObject, NSToolbarDelegate {
    private static let status = NSToolbarItem.Identifier("wire-status")
    private static let settings = NSToolbarItem.Identifier("wire-settings")

    private let controller: RelayController

    init(controller: RelayController) {
        self.controller = controller
    }

    /// The attached toolbar, delegate wired and customization closed off —
    /// there is no palette these items would make sense in.
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "wireframe-chrome")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.status, Self.settings]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        // No border or bezel: the items keep the skin's idiom, not the
        // system toolbar-button chrome.
        item.isBordered = false
        switch id {
        case Self.status:
            item.view = FirstMouseHostingView(rootView: WireStateWord(controller: controller))
        case Self.settings:
            item.view = FirstMouseHostingView(rootView: WireChromeGear(controller: controller))
        default:
            return nil
        }
        return item
    }
}

/// What the run is doing right now, in one word. An indicator, not a
/// control: hit testing is off so a click on it drags the window, the same
/// as the strip around it.
struct WireStateWord: View {
    let controller: RelayController

    var body: some View {
        Text(stateWord)
            .font(Wire.mono(8, .bold))
            .tracking(1.2)
            .foregroundColor(Wire.ink)
            .allowsHitTesting(false)
    }

    private var stateWord: String {
        if controller.isRunning {
            guard controller.isPaused else { return "IN RUN" }
            return controller.isHolding ? "PAUSED" : "PAUSING"
        }
        if controller.hasFinishedRun { return "DONE" }
        if bothReady { return "READY" }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) { return "CHECKING" }
        return "PREP"
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }
}

/// The way into the settings card, kept in the title strip so it is
/// reachable in every console state, mid-run included. The glyph
/// stays small and unboxed — it is a utility, not one of the run controls,
/// and drawing a rectangle around it would give it their weight.
struct WireChromeGear: View {
    let controller: RelayController

    var body: some View {
        Button {
            controller.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: Wire.s(11), weight: .bold))
                .foregroundColor(Wire.faint)
                .frame(width: Wire.s(20), height: Wire.s(20))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(WireHandCursor(active: true))
        .help("Edit the conversation shapes")
    }
}

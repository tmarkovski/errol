import Observation
import SwiftUI

/// Settings and permission setup share the console's window. A missing
/// permission takes precedence over navigation, including after revocation.
@Observable
final class PanelNavigation {
    enum Screen {
        case console, settings, accessibility
    }

    var accessibilityGranted: Bool
    var showsSettings = false
    var consoleWidth = Perch.widgetWidth

    init(accessibilityGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
    }

    var screen: Screen {
        guard accessibilityGranted else { return .accessibility }
        return showsSettings ? .settings : .console
    }
}

/// The screen and native frame use the same smoothstep timing curve.
enum PanelNavigationMotion {
    static let duration = 0.32
    static let animation = Animation.timingCurve(1.0 / 3, 0, 2.0 / 3, 1,
                                                 duration: duration)
}

/// Animate only presentation, leaving destination measurements immediate.
/// Animating layout here would continually restart the native frame animation.
struct PanelScreenPresentation: ViewModifier {
    let isVisible: Bool
    let hiddenOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            // Clear the outgoing text first, so two dense screens do not
            // remain legible on top of each other during the crossfade.
            .animation(reduceMotion ? .easeOut(duration: 0.12)
                       : isVisible ? .easeInOut(duration: 0.24).delay(0.08)
                       : .easeOut(duration: 0.12), value: isVisible)
            .offset(x: isVisible || reduceMotion ? 0 : hiddenOffset)
            .animation(reduceMotion ? nil : PanelNavigationMotion.animation,
                       value: isVisible)
            .disabled(!isVisible)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

/// Fill and clip to the current native frame throughout a resize, while the
/// card inside continues to measure its destination size independently.
///
/// The fill is regular Liquid Glass in the surface's own shape. The window
/// behind it is transparent (MenuBarController.buildPanel), so what shows
/// through is the desktop and the chat windows, blurred; AppKit's native
/// shadow sits around the silhouette, thin rim and all. Regular rather
/// than clear glass, tried and rejected: the panel floats over mostly white
/// chat windows, where clear glass all but disappears and dark-appearance
/// text loses its ground. The bare surface still drags the window.
///
/// The glass goes on the background layer, not on the content. Wrapping the
/// content in `.glassEffect` made AppKit treat every drag inside the panel
/// as a window move (isMovableByWindowBackground), even one that started
/// on a view that opts out of moving the window. Glass behind the content
/// leaves such opt-outs in force, while the same layer carries the drag
/// gesture for the bare surface.
struct PanelWindowSurface: ViewModifier {
    var navigation: PanelNavigation? = nil

    func body(content: Content) -> some View {
        let shape = PanelSurfaceShape(isCard: navigation?.screen == .settings)
        content
            .frame(minWidth: 0, maxWidth: .infinity,
                   minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
                .glassEffect(.regular, in: shape))
            .clipShape(shape)
            .ignoresSafeArea()
    }
}

/// The console and permission setup share one capsule, whose corners follow
/// the current frame. Editors scroll inside that fixed height; Settings
/// retains its conventional corners and separate content size.
struct PanelSurfaceShape: Shape {
    var isCard: Bool

    func path(in rect: CGRect) -> Path {
        let radius = isCard ? Perch.shellCorner : min(rect.width, rect.height) / 2
        return Path(roundedRect: rect, cornerRadius: radius)
    }
}

struct PanelRootView: View {
    let controller: RelayController
    let navigation: PanelNavigation
    var onCardResize: ((CGSize) -> Void)? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        let screen = navigation.screen
        ZStack(alignment: .top) {
            // Keep every screen mounted: navigating, changing appearance, or
            // losing the grant must not discard the native editor, its
            // selection, or drafts.
            PerchConsoleView(controller: controller, width: navigation.consoleWidth)
                // Settings slides the console aside as it comes in. Setup
                // shares the console's capsule, so the two only crossfade.
                .modifier(PanelScreenPresentation(
                    isVisible: screen == .console,
                    hiddenOffset: screen == .settings ? -Perch.s(18) : 0))
                .frame(width: 0, height: screen == .console ? nil : 0, alignment: .top)

            SettingsView(isPresented: screen == .settings)
                .modifier(PanelScreenPresentation(isVisible: screen == .settings,
                                                  hiddenOffset: Perch.s(24)))
                .frame(width: 0, height: screen == .settings ? nil : 0, alignment: .top)

            PermissionOnboardingView(width: navigation.consoleWidth)
                .modifier(PanelScreenPresentation(isVisible: screen == .accessibility,
                                                  hiddenOffset: 0))
                .frame(width: 0, height: screen == .accessibility ? nil : 0, alignment: .top)
        }
        .frame(width: screen == .settings ? Perch.cardWidth : navigation.consoleWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .overlay(alignment: .top) {
            if screen == .settings {
              PerchChrome(controller: controller, screen: screen) {
                if let onBack {
                    onBack()
                } else {
                    navigation.showsSettings = false
                }
              }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            onCardResize?(size)
        }
    }
}

#if DEBUG
#Preview("Settings navigation") {
    let navigation = PanelNavigation(accessibilityGranted: true)
    navigation.showsSettings = true
    return PanelRootView(controller: RelayController(engine: PerchPreviewEngine()),
                         navigation: navigation)
        .background(Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Perch.shellCorner)))
        .clipShape(RoundedRectangle(cornerRadius: Perch.shellCorner))
}

#Preview("Accessibility setup") {
    PanelRootView(controller: RelayController(engine: PerchPreviewEngine()),
                  navigation: PanelNavigation(accessibilityGranted: false))
        .background(Color.clear.glassEffect(.regular, in: Capsule()))
        .clipShape(Capsule())
}
#endif

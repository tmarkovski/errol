import Observation
import SwiftUI

/// Permission setup shares the console's window, and a missing permission
/// covers the console, including after revocation.
@Observable
final class PanelNavigation {
    enum Screen {
        case console, accessibility
    }

    var accessibilityGranted: Bool
    var consoleWidth = Perch.widgetWidth

    init(accessibilityGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
    }

    var screen: Screen { accessibilityGranted ? .console : .accessibility }
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
/// The fill is the theme's shell, a solid color: the prompt box and the
/// conversation summary stand lighter than it (ConsolePalette.Colors). The
/// window is transparent outside the surface's shape
/// (MenuBarController.buildPanel), and AppKit's native shadow sits around
/// the silhouette, thin rim and all. The fill is also the bare surface,
/// which drags the window: it sits behind the content, so a view that opts
/// out of moving the window keeps that opt-out.
struct PanelWindowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity,
                   minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Perch.shell.contentShape(Rectangle()).gesture(WindowDragGesture()))
            // The console and permission setup share one capsule, whose
            // ends follow the current frame.
            .clipShape(Capsule())
            .ignoresSafeArea()
    }
}

struct PanelRootView: View {
    let controller: RelayController
    let navigation: PanelNavigation
    var onCardResize: ((CGSize) -> Void)? = nil

    var body: some View {
        let screen = navigation.screen
        ZStack(alignment: .top) {
            // Keep both screens mounted: changing appearance or losing the
            // grant must not discard the native editor, its selection, or
            // drafts. Setup shares the console's capsule, so the two only
            // crossfade.
            PerchConsoleView(controller: controller, width: navigation.consoleWidth)
                .modifier(PanelScreenPresentation(isVisible: screen == .console, hiddenOffset: 0))
                .frame(width: 0, height: screen == .console ? nil : 0, alignment: .top)

            PermissionOnboardingView(width: navigation.consoleWidth)
                .modifier(PanelScreenPresentation(isVisible: screen == .accessibility,
                                                  hiddenOffset: 0))
                .frame(width: 0, height: screen == .accessibility ? nil : 0, alignment: .top)
        }
        .frame(width: navigation.consoleWidth)
        .fixedSize(horizontal: false, vertical: true)
        // Like the console's editors (GrowingTextEditor), everything here
        // stays out of Writing Tools and so out of macOS 27's "Ask Siri" tag.
        .writingToolsBehavior(.disabled)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            onCardResize?(size)
        }
    }
}

#if DEBUG
#Preview("Accessibility setup") {
    PanelRootView(controller: RelayController(engine: PerchPreviewEngine()),
                  navigation: PanelNavigation(accessibilityGranted: false))
        .background(Perch.shell)
        .clipShape(Capsule())
}
#endif

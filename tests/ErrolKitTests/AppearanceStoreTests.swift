import XCTest
@testable import ErrolKit

final class AppearanceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ErrolAppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNewAndExistingInstallsUseCreamBlueAndFollowSystem() {
        // Existing shape preferences must not stop appearance defaults applying.
        let shapes = SettingsStore(defaults: defaults)
        shapes.updateBody("Keep my edited shape", for: "Debate")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.theme, .creamBlue)
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(SettingsStore(defaults: defaults).template(named: "Debate")?.body,
                       "Keep my edited shape")
    }

    func testChoicesSurviveRelaunchAndCanReturnToDefaults() {
        let store = AppearanceStore(defaults: defaults)
        store.theme = .classicAmber
        store.appearance = .dark
        let reloaded = AppearanceStore(defaults: defaults)
        XCTAssertEqual(reloaded.theme, .classicAmber)
        XCTAssertEqual(reloaded.appearance, .dark)

        reloaded.theme = .creamBlue
        reloaded.appearance = .light
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .light)
        reloaded.appearance = .system
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .creamBlue)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .system)
    }

    func testUnknownStoredChoicesFallBackIndependently() {
        defaults.set("removed-theme", forKey: "appTheme")
        defaults.set("dark", forKey: "appAppearance")
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .creamBlue)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .dark)

        defaults.set("classic-amber", forKey: "appTheme")
        defaults.set("unsupported-appearance", forKey: "appAppearance")
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .classicAmber)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .system)
    }
}

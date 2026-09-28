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

    func testNewAndExistingInstallsUseChalkTealAndFollowSystem() {
        // Other stored preferences must not stop appearance defaults
        // applying, and the store must leave them alone.
        defaults.set("Keep my preference", forKey: "someOtherPreference")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.theme, .chalkTeal)
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(defaults.string(forKey: "someOtherPreference"), "Keep my preference")
    }

    func testFormerBlueThemeUsesChalkTealWithoutChangingAppearance() {
        defaults.set("cream-blue", forKey: "appTheme")
        defaults.set("dark", forKey: "appAppearance")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.theme, .chalkTeal)
        XCTAssertEqual(store.appearance, .dark)
    }

    func testChoicesSurviveRelaunchAndCanReturnToDefaults() {
        let store = AppearanceStore(defaults: defaults)
        store.theme = .classicAmber
        store.appearance = .dark
        let reloaded = AppearanceStore(defaults: defaults)
        XCTAssertEqual(reloaded.theme, .classicAmber)
        XCTAssertEqual(reloaded.appearance, .dark)

        reloaded.theme = .chalkTeal
        reloaded.appearance = .light
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .light)
        reloaded.appearance = .system
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .chalkTeal)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .system)
    }

    func testUnknownStoredChoicesFallBackIndependently() {
        defaults.set("removed-theme", forKey: "appTheme")
        defaults.set("dark", forKey: "appAppearance")
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .chalkTeal)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .dark)

        defaults.set("classic-amber", forKey: "appTheme")
        defaults.set("unsupported-appearance", forKey: "appAppearance")
        XCTAssertEqual(AppearanceStore(defaults: defaults).theme, .classicAmber)
        XCTAssertEqual(AppearanceStore(defaults: defaults).appearance, .system)
    }
}

import CoreGraphics
import XCTest
@testable import ErrolKit

/// The values below are the ones ChatGPT 26.1007 writes to its
/// DockIconPreference and DockIconResourceName keys, and the files its
/// Resources folder ships.
final class ChatGPTDockIconTests: XCTestCase {
    private func resource(_ preference: String?, _ resourceName: String? = nil, dark: Bool) -> String? {
        ChatGPTDockIcon.resource(preference: preference, resourceName: resourceName, dark: dark)
    }

    func testSpaceIconFollowsTheSystemAppearance() {
        XCTAssertEqual(resource("space-system", "icon-space-light.png", dark: false), "icon-space-light.png")
        XCTAssertEqual(resource("space-system", "icon-space-light.png", dark: true), "icon-space-dark.png")
        XCTAssertEqual(resource("space-system", dark: false), "icon-space-light.png")
        XCTAssertEqual(resource("space-system", dark: true), "icon-space-dark.png")
    }

    func testCodexIconFollowsTheSystemAppearance() {
        XCTAssertEqual(resource("codex-system", "icon-codex-light.png", dark: false), "icon-codex-light.png")
        XCTAssertEqual(resource("codex-system", "icon-codex-light.png", dark: true), "icon-codex-dark-color.png")
        XCTAssertEqual(resource("codex-system", dark: true), "icon-codex-dark-color.png")
    }

    func testBuildFlavorSuffixCarriesOverToTheDarkFile() {
        XCTAssertEqual(resource("codex-system", "icon-codex-light-nightly.png", dark: true),
                       "icon-codex-dark-color-nightly.png")
        XCTAssertEqual(resource("space-system", "icon-space-light-beta.png", dark: true),
                       "icon-space-dark-beta.png")
    }

    func testFixedCodexAppearancesIgnoreTheSystem() {
        XCTAssertEqual(resource("codex-light", dark: true), "icon-codex-light.png")
        XCTAssertEqual(resource("codex-dark", dark: false), "icon-codex-dark-color.png")
    }

    func testDefaultMissingAndUnknownPreferencesKeepTheInstalledIcon() {
        XCTAssertNil(resource("app-default", dark: false))
        XCTAssertNil(resource(nil, dark: false))
        XCTAssertNil(resource("space-dark", dark: true))
        XCTAssertNil(resource("galaxy-system", "icon-galaxy-light.png", dark: false))
    }

    func testResourceNameMustBelongToThePreference() {
        // A name stored for another icon, or one reaching outside the
        // Resources folder, is not followed.
        XCTAssertNil(resource("space-system", "icon-codex-light.png", dark: false))
        XCTAssertNil(resource("codex-system", "icon-space-light.png", dark: false))
        XCTAssertNil(resource("space-system", "icon-space-light/../../../etc/x.png", dark: false))
        XCTAssertNil(resource("space-system", "icon-space-light.icns", dark: false))
    }

    func testDockCropTrimsA128thOfTheWidthFromEveryEdge() {
        XCTAssertEqual(ChatGPTDockIcon.dockCrop(width: 1024, height: 1024),
                       CGRect(x: 8, y: 8, width: 1008, height: 1008))
        XCTAssertEqual(ChatGPTDockIcon.dockCrop(width: 2048, height: 2048),
                       CGRect(x: 16, y: 16, width: 2016, height: 2016))
        // Rounded half up, as JavaScript's Math.round does: 960 / 128 = 7.5.
        XCTAssertEqual(ChatGPTDockIcon.dockCrop(width: 960, height: 960),
                       CGRect(x: 8, y: 8, width: 944, height: 944))
    }
}

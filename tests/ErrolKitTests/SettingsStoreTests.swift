// The conversation-shape list behind the panel's picker, editable in the
// settings card. The list is persisted wholesale once it differs from the
// shipped defaults and the stored copy is dropped when it matches them
// again; names stay unique and the list never empties. Each test gets its
// own UserDefaults suite so nothing leaks between tests or into the runner.

import XCTest
@testable import ErrolKit

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ErrolSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshStoreServesTheShippedDefaults() {
        XCTAssertEqual(SettingsStore(defaults: defaults).templates,
                       defaultConversationTemplates)
    }

    func testEditsApplyAndSurviveRelaunch() {
        let store = SettingsStore(defaults: defaults)
        store.updateBody("Argue about the topic below. End when done.", for: "Debate")
        store.updateTopicPrompt("The motion", for: "Debate")

        let reloaded = SettingsStore(defaults: defaults).template(named: "Debate")
        XCTAssertEqual(reloaded?.body, "Argue about the topic below. End when done.")
        XCTAssertEqual(reloaded?.topicPrompt, "The motion")
    }

    func testAddCreatesUniquelyNamedShapesAndPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.addTemplate(), "New shape")
        XCTAssertEqual(store.addTemplate(), "New shape 2",
                       "a second unnamed shape must not collide with the first")
        XCTAssertEqual(SettingsStore(defaults: defaults).templates.count,
                       defaultConversationTemplates.count + 2)
    }

    func testDeleteRemovesTheShape() {
        let store = SettingsStore(defaults: defaults)
        store.deleteTemplate(named: "Debate")
        XCTAssertNil(store.template(named: "Debate"))
        XCTAssertNil(SettingsStore(defaults: defaults).template(named: "Debate"))
    }

    func testDeleteRefusesToEmptyTheList() {
        let store = SettingsStore(defaults: defaults)
        for template in defaultConversationTemplates.dropFirst() {
            store.deleteTemplate(named: template.name)
        }
        store.deleteTemplate(named: defaultConversationTemplates[0].name)
        XCTAssertEqual(store.templates.count, 1,
                       "the picker always needs one shape to point at")
    }

    func testRenameTrimsAndKeepsNamesUnique() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.rename("Brainstorm", to: "  Jam session  "), "Jam session")
        XCTAssertEqual(store.rename("Jam session", to: "Debate"), "Debate 2",
                       "a collision lands under a numbered suffix, not a refusal")
        XCTAssertEqual(store.rename("Debate 2", to: "   "), "Debate 2",
                       "an emptied name field keeps the old name")
    }

    func testRenameKeepsTheCustomEntryReserved() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.rename("Adversary", to: "Custom"), "Custom 2",
                       "the picker's write-from-scratch entry owns the bare name")
    }

    func testResetRestoresShippedTextForDefaultShapes() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.canReset("Debate"))
        store.updateBody("changed", for: "Debate")
        XCTAssertTrue(store.canReset("Debate"))
        store.resetTemplate(named: "Debate")
        XCTAssertEqual(store.template(named: "Debate"),
                       defaultConversationTemplates.first { $0.name == "Debate" })

        store.addTemplate()
        XCTAssertFalse(store.canReset("New shape"),
                       "an added shape has no shipped text to restore")
    }

    func testMatchingTheDefaultsDropsTheStoredCopy() {
        let store = SettingsStore(defaults: defaults)
        let shipped = defaultConversationTemplates[0].body
        store.updateBody("changed", for: defaultConversationTemplates[0].name)
        XCTAssertNotNil(defaults.data(forKey: "conversationTemplates"))
        store.updateBody(shipped, for: defaultConversationTemplates[0].name)
        XCTAssertNil(defaults.data(forKey: "conversationTemplates"),
                     "a list matching the defaults must keep tracking them across updates")
    }
}

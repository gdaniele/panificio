import AppKit
import PanificioCore
import XCTest
@testable import PanificioUI

/// Runs the blocker against a real app, so it hides things on the machine it runs on: only with PANIFICIO_E2E set (CI sets it).
@MainActor
final class BlockerTests: XCTestCase {
    private func wait(_ what: String, until done: () -> Bool) async throws {
        for _ in 0 ..< 100 {
            if done() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for: \(what)")
    }

    private func textEdit() async throws -> NSRunningApplication {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PANIFICIO_E2E"] != nil, "Set PANIFICIO_E2E to run")
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        try await wait("TextEdit to launch") { app.isFinishedLaunching }
        // The next test launches it again, and launching one that's still on its way out fails.
        addTeardownBlock { [self] in
            app.forceTerminate()
            try await wait("TextEdit to quit") { app.isTerminated }
        }
        return app
    }

    func testADeniedAppIsHiddenAtTheStartAndWhenItComesBack() async throws {
        let app = try await textEdit()
        let blocker = Blocker()
        blocker.start(rules: BlockRules(appMode: .block, apps: ["com.apple.TextEdit"]))
        defer { blocker.stop() }
        try await wait("TextEdit to hide at the start") { app.isHidden }

        app.unhide()
        try await wait("TextEdit to come back") { !app.isHidden }
        app.activate(options: [])
        try await wait("TextEdit to hide again") { app.isHidden }
    }

    func testAnAllowListHidesWhatIsOffIt() async throws {
        let app = try await textEdit()
        let blocker = Blocker()
        blocker.start(rules: BlockRules(appMode: .only, apps: ["com.apple.Notes"]))
        defer { blocker.stop() }
        try await wait("TextEdit to hide") { app.isHidden }
    }

    func testAnAppOnTheAllowListStaysOpen() async throws {
        let app = try await textEdit()
        app.unhide()
        let blocker = Blocker()
        blocker.start(rules: BlockRules(appMode: .only, apps: ["com.apple.TextEdit"]))
        defer { blocker.stop() }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(app.isHidden)
    }

    func testStoppingLetsItBackAndHidesNothingNew() async throws {
        let app = try await textEdit()
        let blocker = Blocker()
        blocker.start(rules: BlockRules(appMode: .block, apps: ["com.apple.TextEdit"]))
        try await wait("TextEdit to hide") { app.isHidden }
        blocker.stop()
        app.unhide()
        app.activate(options: [])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(app.isHidden)
    }
}

@MainActor
final class ModelTests: XCTestCase {
    private func model(_ state: AppState = AppState()) throws -> (PanificioModel, Store) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = Store(url: url)
        var quiet = state
        quiet.rules = BlockRules()
        try store.save(quiet)
        return (PanificioModel(store: store, hotkey: false), store)
    }

    func testGivingUpEndsTheSessionAndPaysNothing() throws {
        let (m, store) = try model()
        m.start()
        XCTAssertTrue(m.running)
        m.giveUp()
        XCTAssertFalse(m.running)
        XCTAssertEqual(m.outcome, .lost(0))
        XCTAssertEqual(m.bank, 0)
        XCTAssertEqual(store.load().ledger.entries.count, 1)
        XCTAssertNil(store.load().session)
    }

    func testSettingsLockWhileASessionRuns() throws {
        let (m, _) = try model()
        m.start()
        m.rules = BlockRules(siteMode: .block, sites: ["x.com"])
        m.minutes = 90
        XCTAssertEqual(m.rules, BlockRules())
        XCTAssertEqual(m.minutes, 50)
        m.giveUp()
    }

    func testASessionSurvivesARestartWithoutPayingForTheTimeAway() throws {
        var state = AppState()
        var session = Session(minutes: 25, rules: BlockRules(), now: Date(timeIntervalSinceNow: -7200))
        session.counted = 120
        state.session = session
        let (m, store) = try model(state)
        XCTAssertTrue(m.running)
        XCTAssertEqual(m.bank, 0)
        m.giveUp()
        XCTAssertEqual(m.outcome, .lost(2))
        XCTAssertEqual(store.load().ledger.bank, 0)
    }

    func testTheMenuBarShowsTheBankThenTheClockAndTheStake() throws {
        var state = AppState()
        state.ledger.bank = 120
        let (m, _) = try model(state)
        XCTAssertEqual(m.menuText, "🍞 120")
        m.start()
        XCTAssertEqual(m.menuText, "🔥 50:00 · +0")
        m.giveUp()
    }

    func testTheLoafGainsASliceEveryEighth() {
        XCTAssertEqual(LoafTimer.slices(0), 0)
        XCTAssertEqual(LoafTimer.slices(0.12), 0)
        XCTAssertEqual(LoafTimer.slices(0.5), 4)
        XCTAssertEqual(LoafTimer.slices(1), 8)
    }

    func testClock() {
        XCTAssertEqual(clock(0), "0:00")
        XCTAssertEqual(clock(59.5), "1:00")
        XCTAssertEqual(clock(3599), "59:59")
        XCTAssertEqual(clock(3661), "1:01:01")
    }

    func testFirefoxsAddressBarIsFoundWhicheverRoleItHas() {
        XCTAssertTrue(Blocker.isAddressBar(role: "AXComboBox", words: "urlbar-input search with google or enter address"))
        XCTAssertTrue(Blocker.isAddressBar(role: "AXTextField", words: "urlbar-input"))
        XCTAssertFalse(Blocker.isAddressBar(role: "AXComboBox", words: "search"))
        XCTAssertFalse(Blocker.isAddressBar(role: "AXGroup", words: "urlbar"))
    }
}

import XCTest
@testable import PanificioCore

final class LaserTests: XCTestCase {
    private let firefox = "org.mozilla.firefox"

    func testABrowserKeepsOnlyItsSiteAndItsSubdomains() {
        let aim = Laser.aim(app: firefox, name: "Firefox", isBrowser: true, address: "https://www.github.com/apple/swift", running: false)
        let target = LaserTarget(app: firefox, name: "Firefox", host: "github.com")
        XCTAssertEqual(aim, LaserAim(target: target))
        XCTAssertEqual(target.title, "Firefox · github.com")

        let rules = Laser.rules(for: target)
        XCTAssertTrue(rules.allowsApp(firefox))
        XCTAssertFalse(rules.allowsApp("com.tinyspeck.slackmacgap"))
        XCTAssertTrue(rules.allowsApp("com.apple.finder"), "the system stays open")
        XCTAssertTrue(rules.allowsSite("https://github.com/x"))
        XCTAssertTrue(rules.allowsSite("gist.github.com"))
        XCTAssertFalse(rules.allowsSite("youtube.com"))
        XCTAssertFalse(rules.allowsSite("notgithub.com"))
    }

    func testABrowserWhoseAddressCantBeReadStaysOpenWhole() {
        for address in [nil, "about:blank", "searching for something"] {
            let aim = Laser.aim(app: firefox, name: "Firefox", isBrowser: true, address: address, running: false)
            XCTAssertTrue(aim.missedSite)
            XCTAssertEqual(aim.target, LaserTarget(app: firefox, name: "Firefox"))
            let rules = Laser.rules(for: aim.target!)
            XCTAssertEqual(rules.siteMode, .off)
            XCTAssertTrue(rules.allowsSite("youtube.com"))
            XCTAssertFalse(rules.allowsApp("com.apple.Notes"))
        }
    }

    func testAnAppThatIsntABrowserIgnoresAddresses() {
        let aim = Laser.aim(app: "com.apple.Notes", name: "Notes", isBrowser: false, address: "https://x.com", running: false)
        XCTAssertEqual(aim, LaserAim(target: LaserTarget(app: "com.apple.Notes", name: "Notes")))
        XCTAssertEqual(aim.target?.title, "Notes")
    }

    func testNotWhileASessionRunsAndNotWithoutAnApp() {
        XCTAssertEqual(Laser.unavailable(running: true, app: firefox), "Session running")
        XCTAssertNotNil(Laser.unavailable(running: false, app: nil))
        XCTAssertNil(Laser.unavailable(running: false, app: firefox))
        let aim = Laser.aim(app: firefox, name: "Firefox", isBrowser: true, address: "github.com", running: true)
        XCTAssertNil(aim.target)
        XCTAssertEqual(aim.unavailable, "Session running")
    }

    func testALaserSessionEarnsLikeAnyOther() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let target = LaserTarget(app: "com.apple.Notes", name: "Notes")
        var session = Session(minutes: 25, rules: Laser.rules(for: target), now: start, laser: target)
        for i in 1 ... 25 * 60 { session.tick(now: start.addingTimeInterval(TimeInterval(i))) }
        XCTAssertTrue(session.finished)
        var ledger = Ledger()
        XCTAssertEqual(ledger.complete(session, at: start), 25)
        XCTAssertEqual(ledger.bank, 25)
    }

    func testASessionFromBeforeLasersStillLoads() throws {
        let old = #"{"startedAt":"2027-01-15T08:00:00Z","minutes":50,"counted":60,"lastSeen":"2027-01-15T08:01:00Z","rules":{"appMode":"off","apps":[],"siteMode":"off","sites":[]}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: Data(old.utf8))
        XCTAssertNil(session.laser)
        XCTAssertEqual(session.minutes, 50)
    }
}

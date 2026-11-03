import AppKit
import PanificioCore
import SwiftUI
import XCTest
@testable import PanificioUI

/// Renders the real views to PNGs. Set SNAPSHOT_DIR to keep them; CI uploads them, and docs/ holds the README's.
@MainActor
final class SnapshotTests: XCTestCase {
    private func model(_ state: AppState) throws -> PanificioModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = Store(url: url)
        try store.save(state)
        return PanificioModel(store: store, hotkey: false)
    }

    private func history(_ now: Date = Date()) -> AppState {
        var state = AppState()
        state.rules = BlockRules(appMode: .block, apps: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"],
                                 siteMode: .only, sites: ["developer.apple.com", "github.com"])
        let minutes = [50, 25, 0, 90, 75, 50, 0, 25, 100, 50, 140, 75, 90, 50]
        var bank = 0
        for (i, m) in minutes.enumerated() where m > 0 {
            let day = Calendar.current.date(byAdding: .day, value: i - minutes.count + 1, to: now)!
            state.ledger.entries.append(Entry(startedAt: day, endedAt: day, minutes: m, completed: true))
            bank += m
        }
        state.ledger.bank = bank
        return state
    }

    private func render(_ view: some View, name: String, dark: Bool) throws {
        let host = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.bounds.width, 0)
        XCTAssertGreaterThan(host.bounds.height, 0)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    private func both(_ view: some View, name: String) throws {
        try render(view, name: name, dark: false)
        try render(view, name: name, dark: true)
    }

    func testIdle() throws {
        try both(MenuPanel(model: model(history())), name: "idle")
    }

    func testFirstRun() throws {
        try both(MenuPanel(model: model(AppState())), name: "first-run")
    }

    func testRunning() throws {
        var state = history()
        var session = Session(minutes: 50, rules: BlockRules(), now: Date())
        session.counted = 37 * 60 + 12
        state.session = session
        try both(MenuPanel(model: model(state)), name: "running")
    }

    func testLists() throws {
        try both(ListsView(model: model(history())), name: "lists")
    }

    func testCover() throws {
        try render(BlockCover(blocked: "youtube.com", site: true, stake: 37) {}.frame(width: 960, height: 600), name: "cover", dark: true)
    }
}

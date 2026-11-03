import AppKit
import PanificioCore
import SwiftUI

public enum Outcome: Equatable {
    case banked(Int)
    case lost(Int)
}

/// The app's one source of truth: holds the state, runs the session clock, starts and stops the blocker.
@MainActor
public final class PanificioModel: ObservableObject {
    @Published public private(set) var state: AppState
    /// Ticks while a session runs, so the menu bar and the clock redraw.
    @Published public private(set) var now = Date()
    /// How the last session went, until the next one starts.
    @Published public private(set) var outcome: Outcome?
    /// A laser aimed from the menu or the shortcut, until it starts or is put away.
    @Published public private(set) var laser: LaserAim?
    public let blocker = Blocker()

    private let store: Store
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var savedAt = Date.distantPast
    /// The last app in use that isn't Panificio: opening the menu can bring Panificio to the front, so the laser aims here.
    private var lastApp: NSRunningApplication?
    private var appObserver: NSObjectProtocol?
    private var hotkey: Hotkey?
    private lazy var laserPanel = LaserPanel(model: self)

    /// `hotkey`: listen for ⌃⌥L. Tests leave it off.
    public init(store: Store = .standard, hotkey: Bool = true) {
        self.store = store
        state = store.load()
        blocker.stake = { [weak self] in self?.state.session?.earned ?? 0 }
        // A session open when the app last stopped carries on, with the time away left out.
        if let session = state.session { begin(session) }
        follow(NSWorkspace.shared.frontmostApplication)
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.follow(app) }
        }
        if hotkey { self.hotkey = Hotkey.laser { [weak self] in Task { @MainActor in self?.laserShortcut() } } }
    }

    public var running: Bool { state.session != nil }
    public var bank: Int { state.ledger.bank }
    public var streak: Streak { state.ledger.streak(today: Date()) }
    public var bars: [DayBar] { state.ledger.minutesByDay(days: 14, today: Date()) }

    /// The menu bar: the bank, or the time left and what's at stake.
    public var menuText: String {
        guard let s = state.session else { return "🍞 \(bank)" }
        return "\(s.laser == nil ? "🔥" : "🔦") \(clock(s.left)) · +\(s.earned)"
    }

    // The settings don't change while a session runs: it keeps its own copy of the rules anyway.

    public var rules: BlockRules {
        get { state.rules }
        set { guard !running else { return }; state.rules = newValue; save() }
    }

    public var minutes: Int {
        get { state.minutes }
        set { guard !running else { return }; state.minutes = newValue; save() }
    }

    public func start() {
        guard !running else { return }
        run(Session(minutes: state.minutes, rules: state.rules, now: Date()))
    }

    // MARK: laser

    private func follow(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastApp = app
    }

    /// Aims at the last app in use and, in a browser, its front tab's site. Starts nothing until a length is picked.
    public func aimLaser() {
        let app = lastApp?.isTerminated == false ? lastApp : nil
        let isBrowser = Blocker.isBrowser(app?.bundleIdentifier)
        // A running session's rules stand: no reading browsers for a laser that can't start.
        let address = !running && isBrowser ? app.flatMap { blocker.address(of: $0) } : nil
        laser = Laser.aim(app: app?.bundleIdentifier, name: app?.localizedName, isBrowser: isBrowser, address: address, running: running)
    }

    public func putLaserAway() {
        laser = nil
    }

    /// A laser session: earns like any other, on the laser's own rules instead of the block lists.
    public func startLaser(minutes: Int) {
        guard !running, let target = laser?.target else { return }
        run(Session(minutes: minutes, rules: Laser.rules(for: target), now: Date(), laser: target))
    }

    /// ⌃⌥L: the chooser in a small floating panel, since a menu bar panel can't be opened from code.
    private func laserShortcut() {
        aimLaser()
        laserPanel.show()
    }

    /// All or nothing: ends the session with no pay.
    public func giveUp() {
        guard let session = state.session else { return }
        outcome = .lost(state.ledger.giveUp(session, at: Date()))
        end()
    }

    private func run(_ session: Session) {
        state.session = session
        laser = nil
        outcome = nil
        begin(session)
        save()
    }

    private func begin(_ session: Session) {
        blocker.start(rules: session.rules)
        // The clock counts only what the app watches, so the system mustn't nap it or sleep from idle mid-session.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "A focus session is running")
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func end() {
        state.session = nil
        blocker.stop()
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        save()
    }

    private func tick() {
        guard var session = state.session else { return }
        now = Date()
        session.tick(now: now)
        guard session.finished else {
            state.session = session
            if now.timeIntervalSince(savedAt) >= 5 { save() }
            return
        }
        outcome = .banked(state.ledger.complete(session, at: now))
        end()
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    private func save() {
        savedAt = Date()
        do { try store.save(state) } catch { NSLog("Panificio couldn't save: \(error)") }
    }
}

public func clock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

func hours(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
}

/// The colours. One tomato hue for the marks, a darker step of it under the white label of a prominent button in both
/// modes, and the cover's dark ground.
enum Ink {
    static let sauce = Color(light: 0xB3261E, dark: 0xFF6B5E)
    static let button = Color(light: 0xB3261E, dark: 0xB3261E)
    static let cover = Color(light: 0x1F0F0D, dark: 0x1F0F0D)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

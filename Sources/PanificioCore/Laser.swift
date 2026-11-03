import Foundation

/// What a laser keeps open: one app and, in a browser, one site with its subdomains.
public struct LaserTarget: Codable, Equatable, Sendable {
    /// Bundle identifier.
    public var app: String
    public var name: String
    /// The front tab's host when the app is a browser and its address could be read.
    public var host: String?

    public init(app: String, name: String, host: String? = nil) {
        self.app = app
        self.name = name
        self.host = host
    }

    /// "Firefox · github.com", or just the app.
    public var title: String { host.map { "\(name) · \($0)" } ?? name }
}

/// A laser aimed but not started yet: what it would keep open, or why it can't start.
public struct LaserAim: Equatable, Sendable {
    public var target: LaserTarget?
    /// A browser whose address couldn't be read: the laser keeps the whole browser open.
    public var missedSite: Bool
    /// Why it can't start; nil when it can.
    public var unavailable: String?

    public init(target: LaserTarget?, missedSite: Bool = false, unavailable: String? = nil) {
        self.target = target
        self.missedSite = missedSite
        self.unavailable = unavailable
    }
}

/// Laser: a session that keeps one app open, taken from the app in use, and blocks everything else.
public enum Laser {
    /// The chooser's lengths, in minutes.
    public static let lengths = [25, 50, 90]

    /// Why a laser can't start now; nil when it can. One session at a time, and it needs an app to aim at.
    public static func unavailable(running: Bool, app: String?) -> String? {
        if running { return "Session running" }
        if app == nil { return "Use an app first, then aim the laser at it" }
        return nil
    }

    /// Aims at `app`. A browser keeps only the host its address shows; if that can't be read, the whole browser.
    public static func aim(app: String?, name: String?, isBrowser: Bool, address: String?, running: Bool) -> LaserAim {
        if let why = unavailable(running: running, app: app) { return LaserAim(target: nil, unavailable: why) }
        guard let app else { return LaserAim(target: nil) }
        let host = isBrowser ? address.flatMap(Sites.host(of:)) : nil
        return LaserAim(target: LaserTarget(app: app, name: name ?? app, host: host), missedSite: isBrowser && host == nil)
    }

    /// The session's rules: only the app, and in it only the host and its subdomains.
    public static func rules(for target: LaserTarget) -> BlockRules {
        BlockRules(appMode: .only, apps: [target.app],
                   siteMode: target.host == nil ? .off : .only, sites: target.host.map { [$0] } ?? [])
    }
}

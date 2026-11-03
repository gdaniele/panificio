import Foundation

/// A running session. Its clock only moves while the app is watching: `tick` adds the time since the last tick, unless
/// that gap is too long to have been watched. So sleep, a force quit or a changed system clock can't run the timer down,
/// and the session carries on where it was once the app is back.
public struct Session: Codable, Equatable, Sendable {
    public static let minutesRange = 5 ... 480
    public static let minutesStep = 5
    /// The longest gap between two ticks that still counts as watched. The app ticks twice a second.
    public static let maxGap: TimeInterval = 30

    public var startedAt: Date
    public var minutes: Int
    /// Seconds watched so far.
    public var counted: TimeInterval
    public var lastSeen: Date
    public var rules: BlockRules
    /// What a laser session keeps open; nil for a session on the block lists. Older files have none.
    public var laser: LaserTarget?

    public init(minutes: Int, rules: BlockRules, now: Date, laser: LaserTarget? = nil) {
        startedAt = now
        self.minutes = min(Self.minutesRange.upperBound, max(Self.minutesRange.lowerBound, minutes))
        counted = 0
        lastSeen = now
        self.rules = rules
        self.laser = laser
    }

    public var total: TimeInterval { TimeInterval(minutes * 60) }
    public var left: TimeInterval { max(0, total - counted) }
    public var finished: Bool { counted >= total }
    /// 0 at the start, 1 at the end.
    public var progress: Double { min(1, counted / total) }
    /// One for every whole minute watched: what's at stake, paid only at the end.
    public var earned: Int { min(minutes, Int(counted / 60)) }

    public mutating func tick(now: Date) {
        let gap = now.timeIntervalSince(lastSeen)
        lastSeen = now
        if gap > 0, gap <= Self.maxGap { counted += gap }
    }
}

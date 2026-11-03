import AppKit
import PanificioCore
import SwiftUI

/// The menu bar's panel: the bank and the streak, the session, the last two weeks.
public struct MenuPanel: View {
    private static let sizes: [(name: String, minutes: Int)] = [("Small", 25), ("Medium", 50), ("Large", 90)]

    @ObservedObject var model: PanificioModel
    @Environment(\.openWindow) private var openWindow

    public init(model: PanificioModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(bank: model.bank, streak: model.streak, feeds: model.state.ledger.feeds)
            if let session = model.state.session {
                RunningView(session: session, blocker: model.blocker, giveUp: model.giveUp)
            } else if model.laser != nil {
                LaserChooser(model: model) { model.putLaserAway() }
            } else {
                idle
            }
            Divider()
            Histogram(bars: model.bars)
            Divider()
            HStack {
                Button("Block lists…") { open() }
                // One session at a time: no narrowing a running one.
                Button(model.running ? "🔦 Laser · session running" : "🔦 Laser…") { model.aimLaser() }
                    .disabled(model.running)
                    .help("Keep only the app you were using open, and in a browser only its site. ⌃⌥L from anywhere.")
                Spacer()
                if !model.running { Button("Quit") { NSApp.terminate(nil) } }
            }
            .buttonStyle(.link).foregroundStyle(.secondary).font(.callout)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = outcomeNote {
                Text(note).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(Self.sizes, id: \.minutes) { size in
                    Button(size.name) { model.minutes = size.minutes }
                        .tint(model.minutes == size.minutes ? Ink.sauce : nil)
                        .buttonStyle(.bordered).controlSize(.small).fixedSize()
                }
                Spacer()
                Stepper(value: $model.minutes, in: Session.minutesRange, step: Session.minutesStep) {
                    Text(hours(model.minutes)).monospacedDigit()
                }
                .fixedSize()
            }
            Button(action: model.start) {
                Text("Start · \(model.minutes) dough on the line").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Ink.button).controlSize(.large)
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var outcomeNote: String? {
        switch model.outcome {
        case .banked(let n): return "Fresh from the oven! +\(n) dough"
        case .lost(let n): return n > 0 ? "Burnt. The oven's ready when you are." : "Stopped before the first minute. Nothing lost."
        case nil: return nil
        }
    }

    private var summary: String {
        let r = model.rules
        let apps: String
        switch r.appMode {
        case .off: apps = "All apps open"
        case .block: apps = "\(count(r.apps.count, "app")) blocked"
        case .only: apps = "Only \(count(r.apps.count, "app")) open"
        }
        let sites: String
        switch r.siteMode {
        case .off: sites = "all sites open"
        case .block: sites = "\(count(r.sites.count, "site")) blocked"
        case .only: sites = "only \(count(r.sites.count, "site")) open"
        }
        return "\(apps), \(sites)"
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private func open() {
        openWindow(id: "lists")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct Header: View {
    let bank: Int
    let streak: Streak
    let feeds: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(bank.formatted()).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("dough banked").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(streak.current)").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("days open · best \(streak.best)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Your bakery feeds \(feeds)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RunningView: View {
    let session: Session
    @ObservedObject var blocker: Blocker
    let giveUp: @MainActor () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(clock(session.left)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                LoafTimer(progress: session.progress)
            }
            if let laser = session.laser {
                Text("🔦 Laser on \(laser.title)").font(.callout.weight(.semibold))
            }
            Text("+\(session.earned) dough rising, paid when the timer ends").font(.callout).foregroundStyle(.secondary)
            if !blocker.blind.isEmpty {
                Label("Sites aren't blocked in \(blocker.blind.sorted().joined(separator: ", ")). Allow Panificio in System Settings › Privacy & Security.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if confirming {
                Text("Lose \(session.earned) dough?")
                    .font(.callout.weight(.semibold))
                HStack {
                    Button("Keep going") { confirming = false }
                        .buttonStyle(.borderedProminent).tint(Ink.button)
                    Button("Lose it", role: .destructive, action: giveUp)
                }
            } else {
                Button("Give up…") { confirming = true }
            }
        }
    }
}

/// The session as a round loaf: a slice goes red every eighth of the way. It's drawn from the clock, with no animation of its
/// own, so it changes too rarely to pull the eye.
struct LoafTimer: View {
    let progress: Double

    static func slices(_ progress: Double) -> Int { min(8, Int(progress * 8)) }

    var body: some View {
        ZStack {
            ForEach(0 ..< 8, id: \.self) { i in
                Slice(index: i).fill(i < Self.slices(progress) ? AnyShapeStyle(Ink.sauce) : AnyShapeStyle(.quaternary))
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityElement()
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(Self.slices(progress)) of 8 slices")
    }

    private struct Slice: Shape {
        let index: Int

        func path(in rect: CGRect) -> Path {
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let start = Double(index) * 45 - 90
            var path = Path()
            path.move(to: centre)
            path.addArc(center: centre, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(start + 2),
                        endAngle: .degrees(start + 43), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

/// Completed minutes a day. One series, so no legend: the title names it, a hover reads a bar out.
struct Histogram: View {
    let bars: [DayBar]
    @State private var hovered: Int? = nil

    private var peak: Int { max(bars.map(\.minutes).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Focus, last \(bars.count) days").font(.caption.weight(.semibold))
                Spacer()
                Text(readout).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bars.indices, id: \.self) { column($0) }
            }
            .frame(height: 64)
            HStack {
                Text(bars.first?.day.formatted(.dateTime.day().month()) ?? "")
                Spacer()
                Text("Today")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var readout: String {
        if let i = hovered, bars.indices.contains(i) {
            return "\(bars[i].day.formatted(.dateTime.weekday().day().month())) · \(hours(bars[i].minutes))"
        }
        let total = bars.map(\.minutes).reduce(0, +)
        return total > 0 ? "\(hours(total)) total" : "Nothing yet"
    }

    private func column(_ i: Int) -> some View {
        let minutes = bars[i].minutes
        return GeometryReader { box in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                UnevenRoundedRectangle(topLeadingRadius: minutes > 0 ? 3 : 0, topTrailingRadius: minutes > 0 ? 3 : 0)
                    .fill(minutes > 0 ? AnyShapeStyle(Ink.sauce.opacity(hovered == nil || hovered == i ? 1 : 0.55)) : AnyShapeStyle(.quaternary))
                    .frame(height: minutes > 0 ? max(3, box.size.height * CGFloat(minutes) / CGFloat(peak)) : 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = i } else if hovered == i { hovered = nil }
        }
        .accessibilityElement()
        .accessibilityLabel("\(bars[i].day.formatted(date: .abbreviated, time: .omitted)): \(hours(minutes))")
    }
}

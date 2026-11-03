import AppKit
import PanificioCore
import SwiftUI

/// The laser's chooser: what it keeps open and how long for. Picking a length starts the session.
struct LaserChooser: View {
    @ObservedObject var model: PanificioModel
    let close: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let aim = model.laser {
                if let why = aim.unavailable {
                    Label(why, systemImage: "lock.fill").font(.callout.weight(.semibold))
                    Button("OK") { close() }
                } else if let target = aim.target {
                    Text("🔦 Laser on \(target.title)").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(note(aim, target)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(Laser.lengths, id: \.self) { minutes in
                            Button("\(minutes) min") { model.startLaser(minutes: minutes) }
                                .buttonStyle(.borderedProminent).tint(Ink.button)
                        }
                        Spacer()
                        Button("Not now") { close() }.buttonStyle(.link).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: model.laser) { _, aim in
            if aim == nil { close() }
        }
    }

    private func note(_ aim: LaserAim, _ target: LaserTarget) -> String {
        if aim.missedSite { return "Couldn't read the site, so all of \(target.name) stays open. Every other app is blocked." }
        if target.host != nil { return "Every other app and site is blocked. A dough a minute, paid when the timer ends." }
        return "Every other app is blocked. A dough a minute, paid when the timer ends."
    }
}

/// The shortcut's chooser, in a small floating panel that doesn't take the focus from the app being aimed at.
@MainActor
final class LaserPanel {
    private unowned let model: PanificioModel
    private var panel: NSPanel?
    private var autoClose: Task<Void, Never>?

    init(model: PanificioModel) {
        self.model = model
    }

    func show() {
        let p = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                 styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Laser"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: LaserChooser(model: model) { [weak self] in self?.close() }
            .padding(16).frame(width: 320))
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.center()
        p.orderFrontRegardless()
        panel = p
        autoClose?.cancel()
        autoClose = nil
        // "Session running" and the like only need reading.
        if model.laser?.unavailable != nil {
            autoClose = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled { self?.close() }
            }
        }
    }

    func close() {
        autoClose?.cancel()
        autoClose = nil
        panel?.orderOut(nil)
        model.putLaserAway()
    }
}

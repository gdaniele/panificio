import AppKit
import ApplicationServices
import PanificioCore
import SwiftUI

public struct AppChoice: Identifiable, Equatable {
    public let id: String
    public let name: String
}

/// While a session runs, a blocked app is hidden the moment it comes to the front and a full-screen cover goes over it,
/// with one way back. The front browser's address is read once a second (Safari and the Chrome family by AppleScript,
/// Firefox through Accessibility) and a blocked site gets the same cover, with a way to leave the page.
/// No root, no hosts file, no network filter: it's a commitment device, and the stake does the rest.
@MainActor
public final class Blocker: ObservableObject {
    /// Browsers macOS won't let Panificio read: their sites aren't being blocked, and the user has to know.
    @Published public private(set) var blind: Set<String> = []
    public private(set) var active = false
    /// What the cover says is at stake.
    var stake: () -> Int = { 0 }

    private var rules = BlockRules()
    private var observer: NSObjectProtocol?
    private var panel: NSPanel?
    private var siteTimer: Timer?
    /// The browser whose page the cover is over, if it's a site.
    private var coveredBrowser: String?
    private var askedForAccessibility = false

    public init() {}

    public func start(rules: BlockRules) {
        guard !active else { return }
        self.rules = rules
        active = true
        // A laser's aim may have read a browser before the session: only this session's reads count.
        blind = []
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.check(app) }
        }
        hideBlocked()
        check(NSWorkspace.shared.frontmostApplication)
        if rules.siteMode != .off {
            siteTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkSite() }
            }
        }
    }

    public func stop() {
        active = false
        siteTimer?.invalidate()
        siteTimer = nil
        coveredBrowser = nil
        blind = []
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        hidePanel()
    }

    private func isOwn(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func hideBlocked() {
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !isOwn(app) && !rules.allowsApp(app.bundleIdentifier) {
            app.hide()
        }
    }

    private func check(_ app: NSRunningApplication?) {
        // The cover never goes over this app's own windows.
        if let app, isOwn(app) { hidePanel(); return }
        guard active, let app, app.activationPolicy == .regular, !rules.allowsApp(app.bundleIdentifier) else { return }
        app.hide()
        showPanel(blocked: app.localizedName ?? "That app")
    }

    // MARK: websites

    static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
                                        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "org.chromium.Chromium"]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let firefox: Set<String> = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]

    private func checkSite() {
        // Another app came to the front: the site's cover goes with the browser.
        if let c = coveredBrowser, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != c { coveredBrowser = nil; hidePanel() }
        guard active, let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, rules.allowsApp(id),
              let address = address(of: app, id: id) else { return }
        if rules.allowsSite(address) {
            if coveredBrowser == id { coveredBrowser = nil; hidePanel() }
            return
        }
        guard coveredBrowser != id else { return }
        coveredBrowser = id
        showPanel(blocked: Sites.host(of: address) ?? "That site", site: true)
    }

    /// Whether the blocker can read this app's front tab.
    static func isBrowser(_ id: String?) -> Bool {
        guard let id else { return false }
        return safari.contains(id) || chromium.contains(id) || firefox.contains(id)
    }

    /// The front tab's address, for aiming a laser; nil for an app that isn't a readable browser, or when macOS says no.
    func address(of app: NSRunningApplication) -> String? {
        guard let id = app.bundleIdentifier else { return nil }
        return address(of: app, id: id)
    }

    private func address(of app: NSRunningApplication, id: String) -> String? {
        if Self.safari.contains(id) { return script("tell application id \"\(id)\" to get URL of current tab of front window", app: app) }
        if Self.chromium.contains(id) { return script("tell application id \"\(id)\" to get URL of active tab of front window", app: app) }
        if Self.firefox.contains(id) { return firefoxAddress(pid: app.processIdentifier, app: app) }
        return nil
    }

    /// Runs a one-line AppleScript; nil when it fails (no window, or Automation not allowed: macOS asks once).
    private func script(_ source: String, app: NSRunningApplication) -> String? {
        var error: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
        // errAEEventNotPermitted: the user said no, or hasn't been asked in a way that stuck.
        see(app, denied: error?[NSAppleScript.errorNumber] as? Int == -1743)
        return error == nil ? out?.stringValue : nil
    }

    private func see(_ app: NSRunningApplication, denied: Bool) {
        let name = app.localizedName ?? "A browser"
        if denied { blind.insert(name) } else { blind.remove(name) }
    }

    /// Firefox's address bar, through Accessibility: the focused window's text field or combo box (Firefox 158's bar is
    /// one) whose id or description says url or address.
    static func isAddressBar(role: String?, words: String) -> Bool {
        (role == kAXTextFieldRole as String || role == kAXComboBoxRole as String) && (words.contains("url") || words.contains("address"))
    }

    /// Asks for the Accessibility permission once per launch; the panel names Firefox if it's turned down.
    private func firefoxAddress(pid: pid_t, app browser: NSRunningApplication) -> String? {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !askedForAccessibility] as CFDictionary
        askedForAccessibility = true
        let trusted = AXIsProcessTrustedWithOptions(opts)
        see(browser, denied: !trusted)
        guard trusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success, let window = win else { return nil }
        var seen = 0
        func find(_ el: AXUIElement, _ depth: Int) -> String? {
            seen += 1
            if depth > 14 || seen > 600 { return nil }
            var role: CFTypeRef?, ident: CFTypeRef?, dom: CFTypeRef?, desc: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(el, kAXIdentifierAttribute as CFString, &ident)
            AXUIElementCopyAttributeValue(el, "AXDOMIdentifier" as CFString, &dom)
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc)
            let words = [ident, dom, desc].map { ($0 as? String) ?? "" }.joined(separator: " ").lowercased()
            if Self.isAddressBar(role: role as? String, words: words) {
                var focused: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXFocusedAttribute as CFString, &focused)
                // Being typed in: never judged half-way.
                if (focused as? Bool) == true { return nil }
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
                return value as? String
            }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids)
            for kid in (kids as? [AXUIElement]) ?? [] { if let found = find(kid, depth + 1) { return found } }
            return nil
        }
        return find(window as! AXUIElement, 0)
    }

    /// The site cover's way out: Safari and the Chrome family load a blank page in that tab; Firefox is hidden.
    private func leaveSite() {
        guard let id = coveredBrowser else { hidePanel(); return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        if Self.safari.contains(id), let running {
            _ = script("tell application id \"\(id)\" to set URL of current tab of front window to \"about:blank\"", app: running)
        } else if Self.chromium.contains(id), let running {
            _ = script("tell application id \"\(id)\" to set URL of active tab of front window to \"about:blank\"", app: running)
        } else {
            running?.hide()
        }
        coveredBrowser = nil
        hidePanel()
    }

    private func showPanel(blocked: String, site: Bool = false) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = panel ?? NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.setFrame(screen.frame, display: true)
        p.contentView = NSHostingView(rootView: BlockCover(blocked: blocked, site: site, stake: stake()) { [weak self] in
            if site { self?.leaveSite() } else { self?.hidePanel() }
        })
        p.orderFrontRegardless()
        panel = p
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    /// Apps that could go on a list: everything running, plus /Applications.
    public func candidates() -> [AppChoice] {
        var found: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier { found[id] = app.localizedName ?? id }
        }
        for dir in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".app") {
                if let id = Bundle(path: dir + "/" + name)?.bundleIdentifier { found[id] = found[id] ?? String(name.dropLast(4)) }
            }
        }
        return found.filter { !BlockRules.alwaysAllowed.contains($0.key) && $0.key != Bundle.main.bundleIdentifier }
            .map { AppChoice(id: $0.key, name: $0.value) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

/// The cover over a blocked app or site, and the one way back.
struct BlockCover: View {
    let blocked: String
    var site = false
    var stake = 0
    let back: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("🍞").font(.system(size: 72))
            Text("Your dough is rising.").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("We don't serve \(blocked) here.").font(.title3)
            if stake > 0 {
                Text("Stop now and \(stake) dough is gone.").font(.title3).foregroundStyle(.secondary)
            }
            Button(site ? "Leave the page" : "Back to work", action: back)
                .buttonStyle(.borderedProminent).tint(Ink.button).controlSize(.large).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.cover)
        .environment(\.colorScheme, .dark)
    }
}

# Panificio

A macOS menu bar app that helps you stay focused by blocking distracting apps. It reads your allow/deny list for both macOS applications and websites, and enforces your own rules for the amount of time you decide. You earn a point of dough for every minute you focus, but lose that session's dough if you end it early.

## What it does

- **Sessions** from 5 minutes to 8 hours, or a Small, Medium or Large loaf for 25, 50 or 90 minutes, with the time left and what's at stake in the menu bar.
- **Block lists** for websites and for apps. Each is off, a deny list (*Block these*) or an allow list (*Only these*).
- **Laser.** Press ⌃⌥L, or choose 🔦 Laser in the menu, to focus on the app you were just using for 25, 50 or 90 minutes. Everything else is blocked. In a browser, only that tab's site and its subdomains stay open. It earns like any other session, and it can't start while one runs.
- **All or nothing.** One point of dough for every minute, paid only when the timer ends. Stop early and that session's dough is gone. The bank is safe.
- **Streak and histogram.** Days in a row with a finished session, and your focus minutes over the last 14 days.
- **Your bakery.** It feeds you at first, then your friends, your coworkers, your neighborhood and your city as finished sessions add up. It never shrinks.

Lists lock while a session runs, and a session keeps its own copy of them, so you can't let something through halfway.

## Install

Panificio needs macOS 14 or later.

Build it yourself:

```sh
git clone https://github.com/gdaniele/panificio.git
cd panificio
scripts/build-app.sh
open build/Panificio.app
```

Or download a zip from [Releases](https://github.com/gdaniele/panificio/releases). Those builds aren't notarized, so macOS refuses them at first: try to open the app, then go to System Settings › Privacy & Security and choose **Open Anyway**.

## Permissions

Panificio asks for these only when a session has to read a browser, or a laser is aimed at one:

| Permission | Why |
|---|---|
| Automation (each browser) | Reads the front tab's address in Safari and Chrome-family browsers |
| Accessibility | Reads Firefox's address bar, which has no AppleScript |

If you turn one down, the running session tells you which browser it can't see. Blocking apps needs no permission.

Each build counts as a new app to macOS, so a permission can look on and not work after you update. If Firefox stops being blocked, remove Panificio from System Settings › Privacy & Security › Accessibility and let it ask again.

## How blocking works

Panificio doesn't use root, the hosts file or a network filter. A blocked app is hidden as soon as it comes to the front, and a full-screen cover goes over it. For websites, Panificio checks the front browser's address once a second and covers a blocked page.

That makes Panificio a commitment device, not a prison:

- **Force quitting stops the blocking.** It earns nothing, though. The session's clock only runs while the app is watching, so sleep, a force quit or a changed system clock can't run it down. The session picks up where it stopped when Panificio is back.
- **Only Safari, Chrome, Arc, Brave, Edge, Vivaldi and Firefox are read.** On a website deny list, any other browser gets through, so add it to the apps list.
- **The check covers the front window only**, once a second, so a blocked page can show for a moment.
- **The cover goes on one display**, the one with the app you're using.
- **Other apps' web views aren't seen.** A site inside an Electron app is not a browser tab.

If you want something you can't get out of, use [SelfControl](https://github.com/SelfControlApp/selfcontrol).

## Privacy

Panificio has no account and makes no network calls. Everything it keeps is one JSON file on your Mac, at `~/Library/Application Support/io.github.gdaniele.panificio/state.json`. Browser addresses are read to make a decision and are never stored.

## Develop

`PanificioCore` holds the rules, the session clock and the bank, and it's Foundation only. `PanificioUI` holds the blocker and the views.

```sh
swift test
PANIFICIO_E2E=1 swift test                # also hides and restores a real TextEdit
SNAPSHOT_DIR=snapshots swift test     # also writes the views out as PNGs
```

## License

MIT

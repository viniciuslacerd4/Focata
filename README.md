<div align="center">

<img src="design/icone.png" width="132" alt="Focata icon">

# Focata

**One task at a time in your menu bar, with a Pomodoro you can read at a glance.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-1c2126?style=flat-square)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20and%20Intel-universal-1c2126?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6-1c2126?style=flat-square)
![MIT](https://img.shields.io/badge/license-MIT-1c2126?style=flat-square)

<br>

<img src="design/barra.png" width="234" alt="Focata in the menu bar: a progress ring next to the task">

</div>

<br>

Instead of `24:59, 24:58…`, a ring next to the text fills clockwise, like a download progress indicator. Its color shows the mode: **light for focus**, **green for break time**. A subtle notification lets you know whenever the mode changes. Completing a task does not make it disappear: it stays crossed out until you clear it.

No folders, tags, or priorities. Each of those features would mean one more decision and one more way to procrastinate by organizing instead of doing. The idea of pinning a single task to the menu bar comes from Sindre Sorhus's [One Thing](https://sindresorhus.com/one-thing).

## Download

[**Download the .dmg from the releases page**](../../releases/latest). Open it, drag Focata to the Applications folder, and you're done. It runs on macOS 14 or later, on both Apple Silicon and Intel.

The app is ad hoc signed, without a Developer ID, so macOS will block it the first time. Open **System Settings › Privacy & Security**, scroll down to the warning about Focata, and click **Open Anyway**. If you prefer to handle it in the terminal:

```sh
xattr -d com.apple.quarantine /Applications/Focata.app
```

Once installed, Focata checks GitHub for new versions—when you start your Mac and once a day—and shows an alert when one is available. “Download” takes you straight to the new version's `.dmg`; the other buttons are “Later” and “Skip This Version.” The request is anonymous, nothing you type ever leaves your Mac, and nothing is downloaded without your click. You can turn this off under **Settings › General**, or check on demand from the menu or with the “Check Now” button.

## What it does

<div align="center">
<img src="design/caixa.png" width="430" alt="The task panel, with play/pause, cycle time, and Pomodoro count">
</div>

**In the menu bar**

- One task at a time, with Markdown (bold, italics, strikethrough, links).
- A Pomodoro ring that fills from 0 to 100%, briefly shows a checkmark when the cycle ends, and displays `||` in the center while the session is paused.
- A lock when the session is private.
- A tooltip with the remaining time, for when you want the exact number.

**Workflow**

- Click the **ring** to start or pause a focus session; click the **text** to open the centered task panel.
- The panel has its own title bar: play/pause, cycle time, the task's Pomodoro count, a minimize button, and an ellipsis menu with the same options as the context menu.
- The panel grows with the text up to five lines, always from the bottom edge; beyond that, the field scrolls internally while keeping the cursor visible.
- `return`/`esc` minimize the panel, **shift**+click clears it, and right-click opens the menu.
- Drag an item from Reminders, Things, or any text onto the icon to set the task.
- The round check button in the panel completes the task: it is added to the history and the menu bar is cleared for the next one.
- With the panel open, a completed task leaves the stage before the field goes blank: the strikethrough crosses one line at a time—with the sound of chalk on paper for each stroke—the text dissolves, and the prompt for the next task rises into place.
- If you prefer to keep the crossed-out text visible (**Settings › Pomodoro**), the check button becomes a toggle: click it again to reopen the task.

**History**

- Completed and abandoned tasks, with their date and Pomodoro count.
- Depends on the “Clear the menu bar” option. When crossed-out text remains visible, completion can be undone with the check button—and an entry that can be undone is not really a record. In this mode, nothing is added to the history, whether completed or abandoned.
- Delete entries one by one, or clear everything.
- **Private mode**: the session runs normally but leaves no trace.

**Settings** are organized into four tabs: General, Appearance, Pomodoro, and Shortcuts.
General includes launch at login, history, editor behavior, and update checks, with the installed version in plain view.
Appearance includes prefix/suffix, maximum width, font size, font width, bold, and color.
Durations are adjustable (default 25/5/15, with a long break every 4 cycles), with *Classic 25/5*, *Long 50/10*, and *Sprint 15/3* presets.

## Automation

You can control Focata without touching the menu bar.

**URL scheme**

```sh
open --background 'focata:?text=Exercise'   # sets the task
open --background 'focata://start'          # starts or resumes
open --background 'focata://pause'
open --background 'focata://toggle'
open --background 'focata://skip'           # skips the cycle (does not count as a Pomodoro)
open --background 'focata://reset'          # returns to focus and resets the count
open --background 'focata://complete'       # completes the task (text remains crossed out)
open --background 'focata://clear'
open --background 'focata://edit'            # opens the editor
open --background 'focata://private?on=1'    # without `on`, toggles the setting
```

**Terminal**

```sh
defaults read dev.vinicius.focata text
```

**Shortcuts app:** Set Task, Get Current Task, Start Focus, Pause Timer, Skip Cycle, Complete Task, Toggle Private Mode.

**Services:** select text in any app and choose *Services › Send to Focata*.

**Global shortcuts:** five, configurable in the Shortcuts tab. None are assigned by default, so they do not take over keys you already use.

## Build

Requires macOS 14+ and Xcode 26+.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Focata.xcodeproj -scheme Focata -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Focata.app
```

Alternatively, use `./scripts/build.sh` (accepts `debug`, `release`, or `test`).

`project.yml` is the source of truth: the `.xcodeproj` is generated and is not committed to the repository. Signing is ad hoc (`CODE_SIGN_IDENTITY: "-"`, with no `DEVELOPMENT_TEAM`), so anyone can clone and build it without configuring anything.

To create the installer:

```sh
./scripts/dmg.sh          # → dist/Focata-<version>.dmg
```

The script builds the Release configuration, creates a disk image containing the app and a shortcut to Applications, adjusts the window layout, and compresses it.

## Tests

```sh
xcodebuild -project Focata.xcodeproj -scheme Focata -derivedDataPath build test
```

62 tests cover the Pomodoro engine (transitions, a long break every N cycles, pause/resume, clock jumps caused by sleep), history (persistence, completed and abandoned tasks, private mode), the Markdown renderer, URL parser, and update checker (version comparison, release parsing, daily interval, skipped version). The engine and update checker use an injectable clock, so 25 minutes—or an entire day—pass whenever the test tells them to.

## How it is built

- **Swift 6 + AppKit + SwiftUI.** A pure AppKit lifecycle, with SwiftUI screens hosted in `NSHostingView`.
- **The task panel is a floating `NSPanel`** with a title bar drawn in SwiftUI: without a Dock icon or app menu, this is where the timer, Pomodoro count, and menu live. Minimizing means returning to the menu bar item.
- **The menu bar content is an `NSImage`**, not an `NSView` inside the button: on modern macOS, the item is hosted remotely by Control Center, and a subview with Auto Layout conflicts with that hosting.
- **All progress is derived from absolute dates**, never by counting ticks. This is what lets the timer survive while the Mac is asleep. Sleeping for four hours earns one Pomodoro, not four.
- **A single action facade** (`AppActions`) serves the menu, URL scheme, Shortcuts, Services, and keyboard shortcuts, so “skip cycle” behaves the same no matter where it comes from.
- **Preferences are stored in `UserDefaults`**, and history as JSON in Application Support—easy to delete entry by entry and export, with no schema migrations.
- **Updates are notifications, not automatic installations.** The app is ad hoc signed and distributed as a `.dmg`; the reliable approach is to ask GitHub for the latest release and open the download. Nothing is silently replaced on your Mac.
- **No App Sandbox**, by choice: this is what enables the Services menu and `defaults read`.

## License

MIT. See [LICENSE](LICENSE).

Focata uses Sindre Sorhus's [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), licensed under MIT.

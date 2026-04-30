# Tail Gui

A native macOS menu-bar utility that auto-detects running `tail -f` processes watching [Draw Things](https://drawthings.ai) render output, and shows their live progress as a structured dashboard — not raw log spam.

If you trigger Draw Things renders from background tasks (e.g. via Claude Code), Tail Gui watches the task output files and turns them into a glanceable, floating GUI: passes, clips, current step, ETA, and recent history.

## Features

- **🎦 Menu-bar app** — lives in your menu bar, no Dock icon. Click to show/hide the window.
- **Auto-detect tails** — periodically scans running processes for `tail -f` invocations on Draw Things render output files. No paths to paste, no file pickers.
- **Structured render dashboard** — parses the Draw Things log into:
  - **Header** — output folder, gRPC connection status, render settings (resolution · steps · frames · fps · cfg · sampler)
  - **Overall progress** — clips done / total, progress bar, current pass, percentage, ETA from average clip time
  - **Current clip** — clip index `[N/M]`, name, source (← keyframe / last_frame_of_X), prompt, live `step N/40` bar
  - **Recent clips** — last completed clips with frame count and duration
- **Floating window** — pin it on top of other apps (⌘P).
- **Adjustable transparency** — popover with slider + 100/85/70/50/35% presets.
- **Light / Dark appearance** — binary toolbar toggle (⇧⌘D).
- **Raw log fallback** — toggle to view the unparsed output if you ever need it.
- **Native-feeling** — `NavigationSplitView`, SF Symbols, system materials, HIG-correct toolbar idioms.

## Featured UI patterns

Two reusable cluster patterns at the top of the window — designed to be portable into other floating-utility apps you build:

- **Sidebar Toggle** (top-left, just right of the traffic lights) — the auto-inserted collapse/expand button from `NavigationSplitView`. With `.windowStyle(.hiddenTitleBar)` it lives inside the sidebar's material; when the sidebar fully collapses, macOS automatically wraps it in a soft rounded glass-material chip.
- **HoverToggles** (top-right) — three controls that govern how the app *appears*: appearance toggle (Light ↔ Dark, ⇧⌘D), opacity dropdown with slider + 5 presets, and pin-on-top (⌘P). Designed for "power-multiplier" floating utilities where a designer needs to see what's underneath: light/dark for visibility against any backdrop, opacity for see-through, pin for keeping it on top.

The pin button uses `Toggle(isOn:).toggleStyle(.button)` so macOS automatically tints its container with the system accent color when active — the same blue-padded highlight you see on Activity Monitor's "Keep on Top." HoverToggles are positioned to the trailing edge via a `ToolbarItem(placement: .principal) { Spacer() }` trick (a workaround for a SwiftUI / NavigationSplitView quirk where `.primaryAction` items pack at the leading edge of the detail pane instead of the window's true trailing edge).

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (ships with the Xcode Command Line Tools)
- A Draw Things render workflow that writes streaming progress to a file you watch with `tail -f`

## Building

```bash
git clone https://github.com/<your-username>/tail-gui.git
cd tail-gui

# Quick dev iteration (terminal-launched, no .app bundle):
swift run TailGui

# Build a real .app for Finder/Spotlight/Dock launching:
./scripts/make-app.sh
open ./TailGui.app

# Open in Xcode for IDE work:
open Package.swift
```

The `make-app.sh` script wraps the SwiftPM-built binary in a minimal `.app` bundle with `LSUIElement=true` (menu-bar app, no Dock icon).

### Customizing the bundle identifier

The default is `com.example.tailgui`. Override it for your own builds:

```bash
TAILGUI_BUNDLE_ID="com.yourname.tailgui" ./scripts/make-app.sh
```

## How it detects Draw Things renders

1. Every 2 seconds, the app shells out to `/bin/ps -ax -o pid=,command=` and parses for `tail` invocations using `-f` / `-F`.
2. Each unique target file is checked against a path heuristic: Claude Code task outputs (`/private/tmp/claude-{uid}/.../tasks/{id}.output`).
3. The first 16 KB of the file is scanned for Draw Things markers (`DRAW THINGS`, `/Renders/Batch_`, `Pinging gRPC`, `step N/M`, `[clip N/M]`, etc.). If two soft markers or one strong marker hits, it's promoted to **confirmed**. Empty files stay **pending** and re-evaluate on each scan.
4. Confirmed sessions get an event-driven file watcher (`DispatchSource.makeFileSystemObjectSource`) that streams content incrementally — no polling jitter. File rotation, truncation, and rename are handled.

The active log buffer is capped at the last 256 KB so a multi-hour render won't balloon memory.

## Sandbox

The app is **not** sandboxed. Sandboxing breaks `/bin/ps` enumeration and reads under `/private/tmp/claude-*`, which are essential for what this tool does. This is fine for a personal utility; it would need rethinking for Mac App Store distribution.

The app only sees `tail -f` processes owned by your uid — other users' tails are invisible. No Full Disk Access prompt is required.

## Project layout

```
Package.swift                        - SwiftPM manifest (executable target, macOS 14)
scripts/make-app.sh                  - wraps the built binary into TailGui.app
Sources/TailGui/
  TailGuiApp.swift                   - @main, single-Window scene, color-scheme wiring
  AppDelegate.swift                  - accessory activation policy, NSStatusItem, menu bar
  Models/
    TailProcess.swift                - struct: pid, file path, discoveredAt
    TailSession.swift                - per-tail state: content buffer, status, render state
    RenderState.swift                - parsed Draw Things state (header + progress + history)
  Services/
    ProcessScanner.swift             - /bin/ps shell-out, parses tail -f rows
    DrawThingsDetector.swift         - path heuristic + 16 KB content scan, verdict cache
    DrawThingsParser.swift           - turns log text into RenderState
    FileTailer.swift                 - DispatchSource-based incremental file reader
    TailMonitor.swift                - 2s scan, diffs, owns sessions
  Window/
    WindowAccessor.swift             - SwiftUI <-> NSWindow bridge
    WindowController.swift           - window.level, alphaValue, persistence
    VisualEffectView.swift           - NSVisualEffectView wrapper for material backgrounds
  Views/
    ContentView.swift                - NavigationSplitView host
    SidebarView.swift                - detected-tails list + empty state
    TailRowView.swift                - sidebar row (file name, task hint, age, status pill)
    DetailView.swift                 - dashboard / raw toggle, header + cards
    DashboardCards.swift             - RenderHeaderCard, OverallProgressCard, CurrentClipCard, RecentActivityCard, ProgressBar
    ToolbarContent.swift             - appearance toggle, opacity popover, pin
  Utilities/
    PathParsing.swift                - extract sessionUUID prefix + project slug from Claude Code paths
    DateFormatting.swift             - relative date formatting
    Persistence.swift                - UserDefaults keys, AppearanceMode enum
```

## Architecture notes

- **`TailMonitor`** is the orchestrator: a 2 s timer that diffs scan results, spawns a `TailSession` + `FileTailer` for each new Draw Things tail, and tears them down when the process disappears.
- **`TailSession`** owns the in-memory rolling buffer and re-runs the parser on every append, so SwiftUI sees a fresh `RenderState` reactively.
- **`FileTailer`** is the only place that touches POSIX file descriptors and `DispatchSource` — easy to test in isolation by `echo`-ing into a temp file.
- **`WindowController`** is the only place that touches `NSWindow` properties. The toolbar binds to it and it persists pin/alpha to UserDefaults.

## License

No license currently — all rights reserved by default. Treat this as a personal-utility reference implementation. If you want to use or adapt it, open an issue.

## Acknowledgements

Built collaboratively with [Claude Code](https://claude.com/claude-code).

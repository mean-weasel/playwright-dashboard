# Settings Pane — Design Spec

## Overview

Add a native macOS Settings window (Cmd+,) with two user-facing controls: stale threshold and launch-at-login. No tab navigation — a single-pane form.

## Setting 1: Stale Threshold

### UI

- Label: "Mark sessions stale after"
- Control: SwiftUI `Picker` with `.segmented` or `.menu` style
- Options: 1 min, 2 min (default), 5 min, 10 min, Never
- "Never" disables stale detection entirely

### Storage

- `@AppStorage("staleThresholdSeconds")` — `Int`, default `120`
- "Never" represented as `0` (sentinel value meaning "disabled")

### Wiring

- `ScreenshotService` currently has `private let staleThreshold: TimeInterval = 120`
- Replace with a read from `UserDefaults.standard` (since `ScreenshotService` is not a View, it can't use `@AppStorage` directly — it reads `UserDefaults.standard.integer(forKey: "staleThresholdSeconds")`)
- When value is `0`, skip stale detection entirely (never mark sessions as stale)

## Setting 2: Launch at Login

### UI

- Label: "Launch at login"
- Control: SwiftUI `Toggle`

### Storage

- `@AppStorage("launchAtLogin")` — `Bool`, default `false`

### Implementation

- LaunchAgent plist approach (not SMAppService — that silently fails with ad-hoc signed apps)
- On toggle ON: write `~/Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist` pointing to the app's executable
- On toggle OFF: remove the plist file
- On app launch: sync the toggle state with whether the plist file exists (handles manual deletion)

### LaunchAgent Plist Content

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.neonwatty.PlaywrightDashboard</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/PlaywrightDashboard</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

The `ProgramArguments` path is resolved at write-time from `Bundle.main.executablePath` (for .app bundles) or `CommandLine.arguments[0]` (for dev builds).

## Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Settings/SettingsView.swift` | Create | Settings form with stale threshold picker + launch toggle |
| `Services/LaunchAtLoginManager.swift` | Create | Writes/removes LaunchAgent plist, syncs state on launch |
| `App/PlaywrightDashboardApp.swift` | Modify | Add `Settings { SettingsView() }` scene |
| `Services/ScreenshotService.swift` | Modify | Read stale threshold from UserDefaults instead of hardcoded 120 |

## Constraints

- No new dependencies.
- All files under 300 lines.
- Must pass `swift-format lint`.
- Existing 37 tests must continue passing.
- No tab navigation (only 2 settings don't warrant it).

## Success Criteria

1. Cmd+, opens a Settings window with both controls.
2. Changing stale threshold immediately affects when sessions are marked stale.
3. Toggle launch-at-login ON creates the LaunchAgent plist; OFF removes it.
4. App launch syncs toggle state with plist file existence.
5. Build passes with zero warnings; lint and file-size checks pass.

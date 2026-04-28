# Settings Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native macOS Settings window (Cmd+,) with stale threshold picker and launch-at-login toggle.

**Architecture:** A `Settings` scene in the SwiftUI App struct opens a `SettingsView` form. The stale threshold is stored in `@AppStorage` and read by `ScreenshotService` via `UserDefaults`. Launch-at-login writes/removes a LaunchAgent plist file.

**Tech Stack:** SwiftUI (Settings scene, Form, Picker, Toggle), UserDefaults, FileManager, PropertyListSerialization.

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `Views/Settings/SettingsView.swift` | Settings form UI | Create |
| `Services/LaunchAtLoginManager.swift` | Write/remove LaunchAgent plist | Create |
| `App/PlaywrightDashboardApp.swift` | App scene declarations | Add `Settings` scene |
| `Services/ScreenshotService.swift` | Screenshot capture + stale detection | Read threshold from UserDefaults |

---

### Task 1: LaunchAtLoginManager

**Files:**
- Create: `PlaywrightDashboard/Sources/PlaywrightDashboard/Services/LaunchAtLoginManager.swift`

- [ ] **Step 1: Create the manager**

```swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "LaunchAtLogin")

enum LaunchAtLoginManager {
  private static let plistPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(
      "Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist"
    ).path
  }()

  /// Whether the LaunchAgent plist currently exists on disk.
  static var isEnabled: Bool {
    FileManager.default.fileExists(atPath: plistPath)
  }

  /// Install the LaunchAgent plist so the app starts at login.
  static func enable() {
    let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]

    let plist: [String: Any] = [
      "Label": "com.neonwatty.PlaywrightDashboard",
      "ProgramArguments": [executablePath],
      "RunAtLoad": true,
      "KeepAlive": false,
    ]

    let dir = (plistPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)

    do {
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: URL(fileURLWithPath: plistPath))
      logger.info("LaunchAgent installed at \(plistPath)")
    } catch {
      logger.warning("Failed to write LaunchAgent: \(error.localizedDescription)")
    }
  }

  /// Remove the LaunchAgent plist.
  static func disable() {
    do {
      try FileManager.default.removeItem(atPath: plistPath)
      logger.info("LaunchAgent removed")
    } catch {
      logger.debug("LaunchAgent removal skipped: \(error.localizedDescription)")
    }
  }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Services/LaunchAtLoginManager.swift`
Expected: No warnings.

- [ ] **Step 4: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Services/LaunchAtLoginManager.swift
git commit -m "feat: add LaunchAtLoginManager for LaunchAgent plist install/remove"
```

---

### Task 2: SettingsView

**Files:**
- Create: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Create the settings view**

```swift
import SwiftUI

struct SettingsView: View {
  @AppStorage("staleThresholdSeconds") private var staleThresholdSeconds = 120
  @AppStorage("launchAtLogin") private var launchAtLogin = false

  private let thresholdOptions: [(label: String, seconds: Int)] = [
    ("1 minute", 60),
    ("2 minutes", 120),
    ("5 minutes", 300),
    ("10 minutes", 600),
    ("Never", 0),
  ]

  var body: some View {
    Form {
      Picker("Mark sessions stale after", selection: $staleThresholdSeconds) {
        ForEach(thresholdOptions, id: \.seconds) { option in
          Text(option.label).tag(option.seconds)
        }
      }

      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
          if enabled {
            LaunchAtLoginManager.enable()
          } else {
            LaunchAtLoginManager.disable()
          }
        }
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .onAppear {
      // Sync toggle with actual plist state on disk
      launchAtLogin = LaunchAtLoginManager.isEnabled
    }
  }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Settings/SettingsView.swift`
Expected: No warnings.

- [ ] **Step 4: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Settings/SettingsView.swift
git commit -m "feat: add SettingsView with stale threshold picker and launch toggle"
```

---

### Task 3: Wire Settings Scene into App

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/App/PlaywrightDashboardApp.swift`

- [ ] **Step 1: Add the Settings scene**

After the `Window("Playwright Dashboard", ...)` block (after line 38), add:

```swift
    Settings {
      SettingsView()
    }
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/App/PlaywrightDashboardApp.swift
git commit -m "feat: register Settings scene for Cmd+, access"
```

---

### Task 4: Wire Stale Threshold to ScreenshotService

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Services/ScreenshotService.swift`

- [ ] **Step 1: Replace hardcoded staleThreshold with UserDefaults read**

Replace line 15:

```swift
  /// How long since last activity before marking a session stale.
  private let staleThreshold: TimeInterval = 120
```

With:

```swift
  /// How long since last activity before marking a session stale.
  /// Read from UserDefaults each cycle so changes in Settings take effect immediately.
  /// A value of 0 means stale detection is disabled.
  private var staleThreshold: TimeInterval {
    let stored = UserDefaults.standard.integer(forKey: "staleThresholdSeconds")
    return TimeInterval(stored > 0 ? stored : (stored == 0 ? 0 : 120))
  }
```

Wait — that logic is wrong for distinguishing "never set" (returns 0) from "explicitly set to 0" (Never). We need to handle the UserDefaults default registration.

Replace line 15 with:

```swift
  /// How long since last activity before marking a session stale.
  /// A value of 0 means stale detection is disabled ("Never").
  private var staleThreshold: TimeInterval {
    let stored = UserDefaults.standard.integer(forKey: "staleThresholdSeconds")
    // UserDefaults returns 0 for unset keys — treat as default (120s)
    // To distinguish: register default in the app delegate or check key existence
    return TimeInterval(stored == 0 ? 120 : stored)
  }
```

Actually, since `@AppStorage("staleThresholdSeconds")` in `SettingsView` has a default of `120`, and `UserDefaults.standard.integer(forKey:)` returns `0` when the key doesn't exist, we need to register the default. The simplest approach: register defaults at app startup, then the computed property is trivial.

**Revised approach — two changes:**

In `PlaywrightDashboardApp.swift`, add default registration in an `init()`:

```swift
  init() {
    UserDefaults.standard.register(defaults: [
      "staleThresholdSeconds": 120
    ])
  }
```

Then in `ScreenshotService.swift`, replace line 14-15:

```swift
  /// How long since last activity before marking a session stale.
  /// 0 means stale detection is disabled ("Never").
  private var staleThreshold: TimeInterval {
    TimeInterval(UserDefaults.standard.integer(forKey: "staleThresholdSeconds"))
  }
```

- [ ] **Step 2: Guard stale detection when threshold is 0**

In `captureAll`, replace the stale detection block (lines 87-93):

```swift
      } else {
        // CDP connection failed — mark stale if inactive long enough
        let threshold = staleThreshold
        if threshold > 0 {
          let staleCutoff = Date().addingTimeInterval(-threshold)
          if (session.status == .active || session.status == .idle)
            && session.lastActivityAt < staleCutoff
          {
            session.status = .stale
          }
        }
      }
```

- [ ] **Step 3: Add UserDefaults default registration in the app**

In `PlaywrightDashboardApp.swift`, add before `var body`:

```swift
  init() {
    UserDefaults.standard.register(defaults: [
      "staleThresholdSeconds": 120
    ])
  }
```

- [ ] **Step 4: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 5: Run full QA**

Run: `cd /Users/neonwatty/Desktop/playwright-dashboard-mockup && make qa`
Expected: lint passes, file-size passes, 37 tests pass.

- [ ] **Step 6: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Services/ScreenshotService.swift \
        PlaywrightDashboard/Sources/PlaywrightDashboard/App/PlaywrightDashboardApp.swift
git commit -m "feat: wire stale threshold from UserDefaults, register defaults"
```

---

### Task 5: Smoke Test

- [ ] **Step 1: Build and launch**

Run: `cd PlaywrightDashboard && swift build && .build/debug/PlaywrightDashboard &`

- [ ] **Step 2: Open Settings**

Press Cmd+, (or menu → PlaywrightDashboard → Settings). Verify a settings window appears with:
- "Mark sessions stale after" picker showing "2 minutes"
- "Launch at login" toggle (off)

- [ ] **Step 3: Change stale threshold**

Select "5 minutes" from the picker. Verify the setting persists (close and reopen settings — still shows 5 minutes).

- [ ] **Step 4: Toggle launch at login**

Turn on. Verify `~/Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist` exists:

Run: `cat ~/Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist`

Turn off. Verify the file is removed:

Run: `ls ~/Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist`
Expected: "No such file or directory"

- [ ] **Step 5: Kill the app**

Run: `pkill -f PlaywrightDashboard`

- [ ] **Step 6: Final format and QA**

Run: `make format && make qa`
If format made changes:
```bash
git add -u
git commit -m "style: apply swift-format"
```

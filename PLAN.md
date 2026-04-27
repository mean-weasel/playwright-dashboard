# Playwright Dashboard — Implementation Plan

## Overview

A native macOS (SwiftUI, macOS 15+) menubar app for monitoring and interacting with headless Playwright browser sessions managed by `playwright-cli`. Replaces `playwright-cli show` with proper session management, live screencasts, full browser interaction, and session history.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Playwright Dashboard.app (SwiftUI, macOS 15+)          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────┐   ┌─────────────┐   ┌───────────────┐   │
│  │  Menubar  │   │  Dashboard  │   │   Expanded    │   │
│  │  Popover  │──>│   Window    │──>│  Session View │   │
│  │ (glance)  │   │   (grid)    │   │  (interact)   │   │
│  └───────────┘   └─────────────┘   └───────────────┘   │
│        │                │                   │           │
│        └────────────────┼───────────────────┘           │
│                         │                               │
│  ┌──────────────────────┴──────────────────────────┐    │
│  │            Session Manager (ObservableObject)     │    │
│  │  - FSEvents watcher on daemon directory          │    │
│  │  - CDP connections per session                   │    │
│  │  - Stale detection (2min threshold)              │    │
│  │  - Auto-labeling (worktree + URL)                │    │
│  └──────────────────────┬──────────────────────────┘    │
│                         │                               │
│  ┌─────────────┐  ┌────┴────┐  ┌───────────────────┐   │
│  │  SwiftData  │  │  CDP    │  │   FSEvents        │   │
│  │  (metadata, │  │  Client │  │   (daemon dir     │   │
│  │   history,  │  │  (pure  │  │    watcher)       │   │
│  │   ordering) │  │  Swift) │  │                   │   │
│  └─────────────┘  └─────────┘  └───────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
         │                    │
         │                    │ WebSocket (CDP)
         │                    ▼
         │         ┌─────────────────────┐
         │         │  Headless Chromium   │
         │         │  (per session)       │
         │         │  - port 55318, etc.  │
         │         └─────────────────────┘
         │
         ▼
  ~/Library/Caches/ms-playwright/daemon/<hash>/*.session
```

## Core Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | macOS 15 Sequoia+ | Latest SwiftUI, Observable macro, your machines all run it |
| UI framework | SwiftUI | Native feel, menubar integration, modern APIs |
| CDP layer | Pure Swift WebSocket | No Node dependency, direct JSON-RPC to browsers |
| Persistence | SwiftData (SQLite) | Custom names, ordering, session history |
| Session discovery | FSEvents on daemon dir | Instant updates, zero polling overhead |
| Screencast | Hybrid: screenshots in grid, live CDP stream when expanded |
| Interaction | Full CDP input forwarding (mouse, keyboard, scroll) |
| App lifecycle | Manual launch (no LaunchAgent) |
| Multi-machine | Local only (architect for future remote) |

## Views & Navigation

### 1. Menubar Popover (Quick Glance)
- Session count badge on menubar icon
- Compact list: thumbnail, auto-label, status, workspace
- Status summary: N active, N idle
- "Open Dashboard" button → opens main window
- Any click on a session → opens Dashboard + expands that session
- "Clean up" button when stale sessions exist

### 2. Dashboard Window (Grid)
- **Sidebar** (source list style):
  - Filter by status: All / Active / Idle
  - Filter by workspace
  - Filter by Claude instance
  - Settings link
- **Grid area**:
  - Fixed-size cards with periodic screenshots (every 2-5s via CDP)
  - Cards show: auto-label, session ID, status badge, workspace, Claude/pane info
  - Drag-to-reorder (persisted in SwiftData)
  - Search/filter bar (Cmd+F)
  - Stale sessions flagged with yellow badge + explanation
- **Double-click card** → expanded session view

### 3. Expanded Session View
- Back button → returns to grid
- **Left**: Full-size live CDP screencast
  - Real browser feel: native cursor, smooth scrolling, keyboard passthrough
  - Screencast controls: screenshot, record GIF, refresh, open CDP inspector
  - "LIVE" indicator with pulse animation
  - "Agent active" warning banner when Claude is sending commands
- **Right panel** (Info tab for MVP):
  - Session metadata: name (editable), ID, status, uptime
  - Browser info: URL, page title, CDP port, engine version
  - Owner: workspace, Claude instance, tmux pane
  - Action buttons: screenshot, navigate, close

### 4. Detached PiP Window (stretch goal)
- Pop any expanded session into its own floating window
- Always-on-top, resizable
- Minimal chrome: just screencast + session name
- Close returns it to the grid

## Data Model (SwiftData)

```swift
@Model
class SessionRecord {
    var sessionId: String          // e.g., "admin-ux-25c2"
    var customName: String?        // user-set label
    var autoLabel: String          // derived from worktree + URL
    var workspaceDir: String       // from .session file
    var workspaceName: String      // last path component
    var cdpPort: Int               // extracted from launch args
    var socketPath: String         // for playwright-cli communication
    var gridOrder: Int             // manual drag ordering
    var status: SessionStatus      // .active, .idle, .closed
    var lastScreenshot: Data?      // JPEG of last known state
    var lastURL: String?
    var lastTitle: String?
    var createdAt: Date
    var closedAt: Date?            // nil if still open
    var lastActivityAt: Date       // for stale detection
}

enum SessionStatus: String, Codable {
    case active   // CDP connected, page navigated
    case idle     // CDP connected, about:blank or no activity
    case stale    // idle > 2 minutes
    case closed   // session file gone
}
```

## CDP Client (Pure Swift)

### Key CDP methods needed:

| Method | Purpose |
|--------|---------|
| `Page.startScreencast` | Live frame stream for expanded view |
| `Page.stopScreencast` | Stop stream when leaving expanded view |
| `Page.captureScreenshot` | Periodic thumbnails for grid cards |
| `Page.navigate` | If user triggers navigation |
| `Input.dispatchMouseEvent` | Forward clicks/scroll |
| `Input.dispatchKeyEvent` | Forward keyboard input |
| `Runtime.evaluate` | Get page title, URL |
| `Target.getTargets` | List browser tabs |
| `Target.activateTarget` | Switch tabs (future) |

### Connection lifecycle:
1. Read `.session` file → get `socketPath` for playwright-cli daemon
2. Parse `browser.launchOptions.args` → extract `--remote-debugging-port=XXXXX`
3. Connect WebSocket to `ws://localhost:XXXXX/devtools/page/<target>`
4. Issue CDP commands, receive events

## FSEvents Watcher

```
Watch: ~/Library/Caches/ms-playwright/daemon/
Events: file create, delete, modify
```

- New `.session` file → parse JSON, create/update SessionRecord, connect CDP
- `.session` file deleted → mark SessionRecord as closed, save last screenshot
- Debounce: 500ms to avoid rapid-fire updates during daemon startup

## Stale Detection

- Every 30s, check all sessions:
  - If status == .idle AND (now - lastActivityAt) > 2 minutes → mark as .stale
  - Activity = any CDP event (page navigation, DOM change, network request)
- Stale sessions get yellow badge in grid + "possibly stale" text
- "Clean up stale" batch action: close all stale sessions via daemon socket

## Auto-Labeling

Priority order (first non-empty wins):
1. User-set `customName` (persisted in SwiftData)
2. Worktree branch name, title-cased: `admin-ux-audit` → "Admin UX Audit"
3. Page title from CDP: "Admin — User Management"
4. Session ID as fallback: `admin-ux-25c2`

## Session History

- When a session closes:
  - Save final screenshot (JPEG, compressed)
  - Record closedAt timestamp
  - Keep status as `.closed`
- History retention: 24 hours, then auto-purge via SwiftData predicate
- Closed sessions shown in a "Recent" section at bottom of sidebar (collapsed by default)

## Conflict Handling (Agent Active Warning)

- When expanded session view is open, monitor CDP events
- If incoming CDP commands arrive from the playwright-cli daemon while user is interacting:
  - Show banner: "Agent is active on this session"
  - Allow user interaction (last writer wins)
  - Banner auto-dismisses after 3s of no agent activity

## Build Phases

### Phase 1: Foundation (MVP)
1. Xcode project setup (macOS 15, SwiftUI App lifecycle)
2. SwiftData model + persistence
3. FSEvents daemon directory watcher
4. Session file parser (JSON → SessionRecord)
5. Menubar icon + popover (session count badge, compact list)
6. Dashboard window with grid view (static thumbnails placeholder)
7. Auto-labeling logic

### Phase 2: Screencasts
8. Pure Swift CDP WebSocket client
9. CDP connection manager (connect/disconnect per session)
10. Periodic screenshots for grid thumbnails (every 3s)
11. Live screencast in expanded view (Page.startScreencast)
12. Screencast rendering in NSImageView/Canvas

### Phase 3: Interaction
13. Mouse event forwarding (click, move, scroll)
14. Keyboard event forwarding
15. Coordinate mapping (view size → page viewport)
16. Smooth scrolling support
17. Agent-active warning banner

### Phase 4: Management
18. Rename sessions (inline edit → SwiftData)
19. Drag-to-reorder in grid (persisted order)
20. Close session action (daemon socket communication)
21. Stale detection + "Clean up" batch action
22. Session history (closed sessions, 24h retention, auto-purge)

### Phase 5: Polish
23. Search/filter in grid (Cmd+F)
24. Sidebar filters (status, workspace, Claude instance)
25. Screencast controls (screenshot save, refresh)
26. Detached PiP windows (stretch goal)
27. Window state persistence (position, size, last filter)

## File Structure

```
PlaywrightDashboard/
├── PlaywrightDashboard.xcodeproj
├── PlaywrightDashboard/
│   ├── App/
│   │   ├── PlaywrightDashboardApp.swift      # @main, MenuBarExtra
│   │   └── AppState.swift                     # Top-level observable state
│   ├── Models/
│   │   ├── SessionRecord.swift                # SwiftData model
│   │   ├── SessionStatus.swift                # Enum
│   │   └── SessionFileConfig.swift            # JSON parsing for .session files
│   ├── Services/
│   │   ├── DaemonWatcher.swift                # FSEvents on daemon dir
│   │   ├── SessionManager.swift               # Orchestrates discovery + CDP
│   │   ├── CDPClient.swift                    # WebSocket + JSON-RPC
│   │   ├── CDPConnection.swift                # Per-session CDP connection
│   │   ├── ScreencastManager.swift            # Frame capture + rendering
│   │   ├── InputForwarder.swift               # Mouse/keyboard → CDP events
│   │   ├── StaleDetector.swift                # Periodic stale checks
│   │   └── AutoLabeler.swift                  # Worktree + URL → label
│   ├── Views/
│   │   ├── Menubar/
│   │   │   ├── MenubarPopover.swift           # Quick-glance popover
│   │   │   └── PopoverSessionRow.swift        # Compact session row
│   │   ├── Dashboard/
│   │   │   ├── DashboardWindow.swift          # Main window container
│   │   │   ├── Sidebar.swift                  # Source list filters
│   │   │   ├── SessionGrid.swift              # Grid of cards
│   │   │   ├── SessionCard.swift              # Individual card
│   │   │   └── SearchBar.swift                # Filter input
│   │   ├── Expanded/
│   │   │   ├── ExpandedSessionView.swift      # Full session view
│   │   │   ├── ScreencastView.swift           # Live screencast renderer
│   │   │   ├── ScreencastControls.swift       # Overlay buttons
│   │   │   ├── SessionInfoPanel.swift         # Right panel details
│   │   │   └── AgentWarningBanner.swift       # Conflict banner
│   │   └── Shared/
│   │       ├── StatusBadge.swift              # Active/idle/stale badge
│   │       ├── SessionThumbnail.swift         # Screenshot thumbnail
│   │       └── StaleWarningView.swift         # Cleanup prompt
│   └── Utilities/
│       ├── FSEventsStream.swift               # Swift wrapper for FSEvents
│       └── JSONRPCMessage.swift               # CDP protocol encoding
├── PlaywrightDashboardTests/
│   ├── CDPClientTests.swift
│   ├── SessionFileParserTests.swift
│   ├── AutoLabelerTests.swift
│   └── StaleDetectorTests.swift
└── README.md
```

## Open Questions / Future

- **GIF recording**: Should "Record GIF" in expanded view use CDP screencast frames assembled into a GIF, or screen-record the NSView?
- **Console/Network tabs**: Mocked in the design but deferred past MVP. Would require `Runtime.consoleAPICalled` and `Network.requestWillBeSent` CDP events.
- **Multi-machine**: Future phase would add SSH tunnel to remote daemon directories. Architecture supports this (SessionManager just needs multiple DaemonWatchers).
- **Tab switching**: Active tab only for MVP. Multi-tab support would use `Target.activateTarget`.

## Dependencies

- **Zero external dependencies** for MVP
- macOS 15 SDK (Xcode 16+)
- Swift 6.0
- SwiftData (built-in)
- Foundation URLSessionWebSocketTask (built-in, for CDP)
- FSEvents C API (bridged from Swift)

## Key Risks

1. **CDP screencast performance**: `Page.startScreencast` sends JPEG frames at up to 30fps. Need to ensure the SwiftUI view can keep up without dropped frames. Mitigation: render into a CALayer/MTKView rather than SwiftUI Image.
2. **Input forwarding accuracy**: Mouse coordinates need precise mapping from app view coordinates to browser viewport coordinates, accounting for device pixel ratio. Mitigation: query viewport size via CDP and compute scale factor.
3. **Daemon socket protocol**: Closing sessions requires talking to the playwright-cli daemon via its Unix socket. Need to reverse-engineer the protocol. Mitigation: we already read the source in session.js — it's a simple JSON-RPC over socket.
4. **Multiple CDP connections**: With 6-12 sessions, each with a WebSocket, need to manage connection lifecycle carefully. Mitigation: only keep screencast active for expanded view; grid uses periodic single-shot screenshots.

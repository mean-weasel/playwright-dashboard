# Expanded Session View — Design Spec

## Overview

A monitor-mode detail view that appears when a user clicks a session card in the grid. Shows a large live-updating screenshot of the browser, a thin info bar with session identity and status, and a collapsible metadata panel.

## Layout

```
┌─────────────────────────────────────────────────────────┐
│ ← Back    ● Active   "Admin UX Redesign"     ⓘ toggle  │
├─────────────────────────────────────────────┬───────────┤
│                                             │ Metadata  │
│                                             │           │
│          Live Screenshot                    │ URL:      │
│          (aspect-fit, centered)             │ Title:    │
│                                             │ Port:     │
│                                             │ Workspace:│
│                                             │ Last seen:│
│                                             │           │
└─────────────────────────────────────────────┴───────────┘
```

### Info Bar (top)

- **Back button**: sets `appState.selectedSessionId = nil`, returns to grid.
- **Status badge**: reuses existing `StatusBadge` component.
- **Display name**: `session.customName ?? session.autoLabel`.
- **Metadata toggle** (ⓘ): shows/hides the right panel. State stored in `@AppStorage("expandedShowMetadata")` so it persists.

### Screenshot Area (main content)

- Renders `session.lastScreenshot` as a `Image(nsImage:)` with `.resizable()` and `.aspectRatio(contentMode: .fit)`.
- Centered in available space with a subtle rounded-rect clip and drop shadow.
- If no screenshot is available yet, shows a placeholder with a progress spinner.
- Updates automatically as the underlying `SessionRecord.lastScreenshot` changes (SwiftData observation).

### Metadata Panel (right, collapsible)

- Fixed width: 220px.
- Fields displayed as label/value pairs:
  - **URL** — `session.lastURL` (truncated, with copy button)
  - **Page Title** — `session.lastTitle`
  - **CDP Port** — `session.cdpPort`
  - **Workspace** — `session.workspaceName` (title-cased via AutoLabeler)
  - **Project** — `session.projectName`
  - **Session ID** — `session.sessionId` (monospace, copyable)
  - **Created** — `session.createdAt` (relative format)
  - **Last Activity** — `session.lastActivityAt` (relative format)
- Hidden by default on windows narrower than 800px (responsive).

## Refresh Behavior

### Fast-Refresh Task

When `selectedSessionId` is non-nil, `ExpandedSessionView` starts a dedicated `Task` that captures a screenshot every 1.5 seconds for the focused session only.

```swift
.task(id: session.sessionId) {
    let client = CDPClient(port: session.cdpPort)
    while !Task.isCancelled {
        do {
            let result = try await client.captureScreenshot(quality: 60)
            session.lastScreenshot = result.jpeg
            session.lastURL = result.url
            session.lastTitle = result.title
            session.lastActivityAt = Date()
            session.status = (result.url != nil && result.url != "about:blank") ? .active : .idle
        } catch is CancellationError {
            break
        } catch {
            // CDP failed — don't change status, just skip this cycle
        }
        try? await Task.sleep(for: .seconds(1.5))
    }
}
```

Key behaviors:
- Uses `.task(id:)` so the task auto-cancels when `session.sessionId` changes or the view disappears.
- Quality bumped from 50 to 60 since this is the "focused" view.
- Does not mark stale on failure (bulk service handles stale transitions).
- The bulk `ScreenshotService` continues its 5-second cycle for all other sessions independently.

### Interaction with Bulk Service

No coordination needed. Both write to the same `SessionRecord.lastScreenshot`. The fast-refresh task overwrites more frequently for the focused session, which is the desired behavior. The bulk service's next write for this session will be overwritten 1.5s later anyway.

## Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Expanded/ExpandedSessionView.swift` | Replace | Main expanded view with screenshot + fast-refresh task |
| `Views/Expanded/SessionInfoBar.swift` | Create | Top bar: back button, status, name, metadata toggle |
| `Views/Expanded/SessionMetadataPanel.swift` | Create | Right panel: metadata label/value pairs |
| `Views/Dashboard/DashboardWindow.swift` | Modify | Wire in `ExpandedSessionView(session:)` |

## Constraints

- No new dependencies — uses existing `CDPClient`, `StatusBadge`, `AutoLabeler`.
- All files must stay under 300 lines (CI gate).
- Must pass `swift-format lint`.
- Read-only — no interaction forwarding in this phase.

## Success Criteria

1. Clicking a session card navigates to the expanded view with a visible screenshot within 2 seconds.
2. Screenshot updates visibly every ~1.5 seconds while the view is active.
3. Back button returns to the grid without orphan tasks.
4. Metadata panel toggles smoothly and persists preference across launches.
5. Build passes with zero warnings; lint and file-size checks pass.

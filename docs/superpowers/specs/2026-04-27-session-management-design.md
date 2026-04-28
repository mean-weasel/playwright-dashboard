# Session Management — Design Spec

## Overview

Add rename, close/reopen, and bulk cleanup capabilities to the dashboard. Currently sessions can only be viewed — there are no management actions. The "Clean up" text in the menubar popover is decorative placeholder with no action.

## Feature 1: Rename Sessions

### Context Menu Rename

Right-click a `SessionCard` to get a context menu with "Rename..." option. This presents a small popover or alert with a `TextField` pre-filled with the current `displayName`. On submit, sets `session.customName` to the entered value. If the field is cleared/empty, `customName` is set to `nil` (reverts to auto-label).

### Expanded View Rename

In `SessionInfoBar`, the display name text is clickable. Clicking it replaces the `Text` with an inline `TextField` for editing. Same submit/cancel behavior as the context menu version.

## Feature 2: Close/Reopen Sessions

### Close from Context Menu

Right-click a session card → "Close Session". Sets `session.status = .closed` and `session.closedAt = Date()`. The session disappears from the default grid view (which filters out closed sessions).

### View Closed Sessions

Add a `.closed` case to `SidebarFilter`. The sidebar shows a "Closed" row (with count) below the existing filters. When selected, the grid shows only closed sessions.

### Reopen from Context Menu

Right-click a closed session card → "Reopen Session". Sets `session.status = .idle` and `session.closedAt = nil`. The session reappears in the normal grid view.

## Feature 3: Bulk Cleanup

### Menubar Popover

Wire the existing "Clean up" `Text` as a real `Button`. Action: marks all `.stale` sessions as `.closed` with `closedAt = Date()`.

### Sidebar

Add a "Clean Up Stale" button in the sidebar footer, visible when stale sessions exist. Same action as the popover button.

## Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Dashboard/SessionCard.swift` | Modify | Add `.contextMenu` with Rename and Close/Reopen |
| `Views/Dashboard/SessionGrid.swift` | Modify | Add rename state management, pass context to cards |
| `Views/Expanded/SessionInfoBar.swift` | Modify | Make display name tappable for inline rename |
| `Views/Dashboard/Sidebar.swift` | Modify | Add `.closed` filter case, "Clean Up Stale" button |
| `Views/Menubar/MenubarPopover.swift` | Modify | Wire "Clean up" as real button |

## Constraints

- No new files — all modifications to existing views.
- No new dependencies.
- All files must stay under 300 lines (CI gate).
- Must pass `swift-format lint`.
- 24 existing tests must continue passing.

## Success Criteria

1. Right-click a session card → Rename, Close options appear.
2. Renaming updates the display name across all views immediately.
3. Closing a session removes it from the grid; it appears under the "Closed" sidebar filter.
4. Reopening a closed session returns it to the main grid.
5. "Clean up" in the popover and sidebar closes all stale sessions.
6. Build passes with zero warnings; lint and file-size checks pass.

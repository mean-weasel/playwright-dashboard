# UI Polish Bundle — Design Spec

## Overview

Three small polish features that improve the feel of the existing dashboard: live thumbnails in the menubar popover, drag-to-reorder in the session grid, and essential keyboard shortcuts.

## Feature 1: Menubar Thumbnails

### Current State

`MenubarPopover.sessionRow()` renders a static gray `RoundedRectangle(cornerRadius: 4)` at 32x22pt as a placeholder thumbnail. `SessionRecord.lastScreenshot` (JPEG `Data?`) is already populated by `ScreenshotService` but not displayed in the popover.

### Change

Replace the placeholder with the session's last screenshot using the same `NSImage(data:)` → `Image(nsImage:)` pattern from `SessionCard.screenshotArea`. Keep the 32x22pt frame, use `.scaledToFill()` with `.clipShape(RoundedRectangle(cornerRadius: 4))`. Fall back to the gray rectangle when `lastScreenshot` is nil.

### Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Menubar/MenubarPopover.swift` | Modify | Replace placeholder with live thumbnail |

## Feature 2: Drag Reorder

### Current State

`SessionGrid` applies `.draggable(session.sessionId)` to each `SessionCard` in both `flatGrid` and `groupedGrid`. However, there is no `.dropDestination` or `.onDrop` — items can be dragged but not dropped. `SessionRecord.gridOrder` is assigned sequentially at creation time and never mutated afterward.

### Change

Add `.dropDestination(for: String.self)` on each card to complete the drag-drop circuit. On drop, find the dragged session and the drop-target session, then swap their `gridOrder` values. This works in both flat and grouped grid modes since both sort by `gridOrder`.

### Drop Logic

```
1. Receive dropped sessionId string
2. Find source session (by sessionId) and target session (the card being dropped onto)
3. Swap source.gridOrder ↔ target.gridOrder
4. SwiftData observation triggers re-sort automatically
```

### Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Dashboard/SessionGrid.swift` | Modify | Add drop destination handler |

## Feature 3: Essential Keyboard Shortcuts

### Current State

No keyboard shortcuts exist anywhere in the app. Session cards require double-click to open. The expanded view has a back button but no keyboard binding.

### Changes

1. **Escape to go back**: Add `.keyboardShortcut(.escape, modifiers: [])` to the back button in `SessionInfoBar`. When in the expanded view, pressing Escape returns to the grid.

2. **Single-click to open**: Replace `.onTapGesture(count: 2)` with `.onTapGesture(count: 1)` in `SessionGrid`. Now that the expanded view has a clear back button and Escape shortcut, double-click is unnecessarily heavy. Rename the `onDoubleClick` closure to `onSelect` for clarity.

### Files

| File | Action | Purpose |
|------|--------|---------|
| `Views/Expanded/SessionInfoBar.swift` | Modify | Add Escape keyboard shortcut to back button |
| `Views/Dashboard/SessionGrid.swift` | Modify | Change double-click to single-click |
| `Views/Dashboard/SessionCard.swift` | Modify | Rename `onDoubleClick` to `onSelect`, change tap count |

## Constraints

- No new files — all modifications to existing views.
- No new dependencies.
- All files must stay under 300 lines (CI gate).
- Must pass `swift-format lint`.
- 19 existing tests must continue passing.

## Success Criteria

1. Menubar popover shows live session thumbnails that update with the screenshot service cycle.
2. Session cards can be dragged and dropped to reorder; the new order persists across app launches (SwiftData).
3. Escape returns from expanded view to grid.
4. Single-click opens a session card into expanded view.
5. Build passes with zero warnings; lint and file-size checks pass.

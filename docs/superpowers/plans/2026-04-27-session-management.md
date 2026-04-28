# Session Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rename, close/reopen, and bulk cleanup actions to the dashboard so users can manage their sessions, not just view them.

**Architecture:** Context menus on session cards provide per-session actions (rename, close/reopen). The sidebar gains a "Closed" filter and a "Clean Up Stale" button. The menubar popover's placeholder "Clean up" text becomes a real button. The expanded view's info bar gets an inline rename capability.

**Tech Stack:** SwiftUI (`.contextMenu`, `TextField`, `@State` for edit mode), SwiftData (@Model mutation).

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `Views/Dashboard/SessionCard.swift` | Session card with context menu | Add `.contextMenu` with Rename and Close/Reopen |
| `Views/Dashboard/SessionGrid.swift` | Grid layout with filtering | Add `.closed` filter case, handle rename alert |
| `Views/Dashboard/Sidebar.swift` | Sidebar navigation | Add `.closed` filter row, "Clean Up Stale" button |
| `Views/Expanded/SessionInfoBar.swift` | Expanded view top bar | Make name tappable for inline rename |
| `Views/Menubar/MenubarPopover.swift` | Menubar popover | Wire "Clean up" as real button |

---

### Task 1: Context Menu on SessionCard

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionCard.swift`

- [ ] **Step 1: Add context menu to the card**

After the `.onTapGesture` modifier (line 58), add a `.contextMenu`:

```swift
    .contextMenu {
      Button("Rename...") {
        onRename?()
      }

      Divider()

      if session.status == .closed {
        Button("Reopen Session") {
          session.status = .idle
          session.closedAt = nil
        }
      } else {
        Button("Close Session", role: .destructive) {
          session.status = .closed
          session.closedAt = Date()
        }
      }
    }
```

- [ ] **Step 2: Add the `onRename` closure property**

After the existing `onSelect` property (line 5), add:

```swift
  var onRename: (() -> Void)?
```

- [ ] **Step 3: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 4: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionCard.swift`
Expected: No warnings.

- [ ] **Step 5: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionCard.swift
git commit -m "feat: add context menu with Rename, Close/Reopen to session cards"
```

---

### Task 2: Rename Alert in SessionGrid

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionGrid.swift`

- [ ] **Step 1: Add rename state properties**

After the `columns` property (line 13), add:

```swift
  @State private var renamingSession: SessionRecord?
  @State private var renameText = ""
```

- [ ] **Step 2: Add an `.alert` for renaming**

After the `.toolbar` modifier (line 38), add:

```swift
    .alert("Rename Session", isPresented: .init(
      get: { renamingSession != nil },
      set: { if !$0 { renamingSession = nil } }
    )) {
      TextField("Session name", text: $renameText)
      Button("Save") {
        if let session = renamingSession {
          session.customName = renameText.isEmpty ? nil : renameText
        }
        renamingSession = nil
      }
      Button("Cancel", role: .cancel) {
        renamingSession = nil
      }
    } message: {
      Text("Enter a custom name for this session, or leave empty to use the auto-generated name.")
    }
```

- [ ] **Step 3: Pass `onRename` to SessionCard in `flatGrid`**

In `flatGrid`, update the `SessionCard` initializer to include `onRename`:

```swift
        SessionCard(
          session: session,
          onSelect: {
            appState.selectedSessionId = session.sessionId
          },
          onRename: {
            renameText = session.displayName
            renamingSession = session
          }
        )
```

- [ ] **Step 4: Pass `onRename` to SessionCard in `groupedGrid`**

Same change in `groupedGrid`:

```swift
              SessionCard(
                session: session,
                onSelect: {
                  appState.selectedSessionId = session.sessionId
                },
                onRename: {
                  renameText = session.displayName
                  renamingSession = session
                }
              )
```

- [ ] **Step 5: Add `.closed` to the filter switch**

In the `filteredSessions` computed property, add a case for `.closed` in the switch:

```swift
    case .closed:
      result = result.filter { $0.status == .closed }
```

Add it between the `.idleStale` case and the `.workspace` case.

- [ ] **Step 6: Handle `.closed` in `isGroupedByWorkspace`**

In the `isGroupedByWorkspace` computed property, add the `.closed` case:

```swift
    case .closed: return false
```

Add it after the `.idleStale` case.

- [ ] **Step 7: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 8: Run lint and check file size**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionGrid.swift && wc -l PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionGrid.swift`
Expected: No warnings. Under 200 lines.

- [ ] **Step 9: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/SessionGrid.swift
git commit -m "feat: add rename alert and closed filter to session grid"
```

---

### Task 3: Sidebar — Closed Filter and Clean Up Button

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/Sidebar.swift`

- [ ] **Step 1: Add `.closed` case to `SidebarFilter`**

In the `SidebarFilter` enum (line 3-7), add the `.closed` case:

```swift
enum SidebarFilter: Hashable {
  case allOpen
  case idleStale
  case closed
  case workspace(String)
}
```

- [ ] **Step 2: Add the "Closed" row to the sidebar**

In the `body`, after the `.idleStale` row (after line 29), add:

```swift
        sidebarRow(
          filter: .closed,
          title: "Closed",
          icon: "xmark.circle.fill",
          iconColor: .secondary,
          count: closedCount
        )
```

- [ ] **Step 3: Add the closedCount computed property**

After `idleStaleCount` (after line 80), add:

```swift
  private var closedCount: Int {
    appState.sessions.filter { $0.status == .closed }.count
  }
```

- [ ] **Step 4: Add a "Clean Up Stale" button in the sidebar**

After the "Workspaces" section closing brace (after line 44), add:

```swift
      if staleCount > 0 {
        Section {
          Button {
            for session in appState.sessions where session.status == .stale {
              session.status = .closed
              session.closedAt = Date()
            }
          } label: {
            Label("Clean Up \(staleCount) Stale", systemImage: "trash")
              .foregroundStyle(.orange)
          }
          .buttonStyle(.plain)
        }
      }
```

- [ ] **Step 5: Add the staleCount computed property**

After `closedCount`, add:

```swift
  private var staleCount: Int {
    appState.sessions.filter { $0.status == .stale }.count
  }
```

- [ ] **Step 6: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 7: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/Sidebar.swift`
Expected: No warnings.

- [ ] **Step 8: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/Sidebar.swift
git commit -m "feat: add Closed filter and Clean Up Stale button to sidebar"
```

---

### Task 4: Inline Rename in SessionInfoBar

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift`

- [ ] **Step 1: Add editing state**

After the `@Binding var showMetadata: Bool` property (line 6), add:

```swift
  @State private var isEditing = false
  @State private var editText = ""
```

- [ ] **Step 2: Replace the static name Text with a tappable/editable version**

Replace:

```swift
      Text(session.displayName)
        .font(.headline)
        .lineLimit(1)
```

With:

```swift
      if isEditing {
        TextField("Session name", text: $editText, onCommit: {
          session.customName = editText.isEmpty ? nil : editText
          isEditing = false
        })
        .font(.headline)
        .textFieldStyle(.plain)
        .frame(maxWidth: 200)
        .onExitCommand {
          isEditing = false
        }
      } else {
        Text(session.displayName)
          .font(.headline)
          .lineLimit(1)
          .onTapGesture {
            editText = session.displayName
            isEditing = true
          }
          .help("Click to rename")
      }
```

- [ ] **Step 3: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 4: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift`
Expected: No warnings.

- [ ] **Step 5: Check file size**

Run: `wc -l PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift`
Expected: Under 70 lines.

- [ ] **Step 6: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift
git commit -m "feat: add inline rename in expanded view info bar"
```

---

### Task 5: Wire Menubar Popover "Clean Up" Button

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Menubar/MenubarPopover.swift`

- [ ] **Step 1: Replace the placeholder "Clean up" Text with a real Button**

In `summaryStrip` (around lines 71-75), replace:

```swift
        if !staleSessions.isEmpty {
          Text("Clean up")
            .font(.caption)
            .foregroundStyle(.blue)
        }
```

With:

```swift
        if !staleSessions.isEmpty {
          Button {
            for session in staleSessions {
              session.status = .closed
              session.closedAt = Date()
            }
          } label: {
            Text("Clean up")
              .font(.caption)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.blue)
        }
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Menubar/MenubarPopover.swift`
Expected: No warnings.

- [ ] **Step 4: Run full QA**

Run: `cd /Users/neonwatty/Desktop/playwright-dashboard-mockup && make qa`
Expected: lint passes, file-size passes, 24 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Menubar/MenubarPopover.swift
git commit -m "feat: wire menubar Clean Up button to close stale sessions"
```

---

### Task 6: Smoke Test

- [ ] **Step 1: Build and launch**

Run: `cd PlaywrightDashboard && swift build && .build/debug/PlaywrightDashboard &`

- [ ] **Step 2: Verify context menu**

Right-click a session card. Verify "Rename..." and "Close Session" appear.

- [ ] **Step 3: Verify rename**

Right-click → "Rename...". Enter a new name. Verify the name updates in the card, sidebar, and menubar popover.

- [ ] **Step 4: Verify close/reopen**

Right-click → "Close Session". Verify the session disappears from the grid. Click "Closed" in the sidebar. Verify the closed session appears. Right-click → "Reopen Session". Verify it returns to the main grid.

- [ ] **Step 5: Verify inline rename in expanded view**

Open a session. Click the name in the info bar. Verify a text field appears. Type a new name and press Enter. Verify it updates.

- [ ] **Step 6: Verify bulk cleanup**

Click the menubar icon. If stale sessions exist, click "Clean up". Verify stale sessions are closed. Check the sidebar "Clean Up Stale" button does the same.

- [ ] **Step 7: Kill the app**

Run: `pkill -f PlaywrightDashboard`

- [ ] **Step 8: Final format and QA**

Run: `make format && make qa`
If format made changes:
```bash
git add -u
git commit -m "style: apply swift-format"
```

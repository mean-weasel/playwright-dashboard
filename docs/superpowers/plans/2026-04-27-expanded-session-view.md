# Expanded Session View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a monitor-mode detail view that shows a large live-updating browser screenshot (1.5s refresh), info bar, and collapsible metadata panel when a user clicks a session card.

**Architecture:** Three focused SwiftUI views compose the expanded view: `SessionInfoBar` (top navigation/status), `SessionMetadataPanel` (right collapsible panel), and `ExpandedSessionView` (orchestrator with fast-refresh Task). The view reads from the existing `SessionRecord` @Model and uses `CDPClient` directly for its dedicated capture loop.

**Tech Stack:** SwiftUI, SwiftData (@Model observation), CDPClient actor, AppStorage for preference persistence.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `Sources/.../Views/Expanded/SessionInfoBar.swift` | Top bar: back button, status badge, display name, metadata toggle |
| `Sources/.../Views/Expanded/SessionMetadataPanel.swift` | Right panel: label/value metadata pairs with copy buttons |
| `Sources/.../Views/Expanded/ExpandedSessionView.swift` | Orchestrator: layout, fast-refresh task, panel state |
| `Sources/.../Views/Dashboard/DashboardWindow.swift` | Wire expanded view in place of placeholder |

---

### Task 1: SessionInfoBar

**Files:**
- Create: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift`

- [ ] **Step 1: Create the info bar view**

```swift
import SwiftUI

struct SessionInfoBar: View {
  let session: SessionRecord
  let onBack: () -> Void
  @Binding var showMetadata: Bool

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onBack) {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.plain)

      StatusBadge(status: session.status)

      Text(session.customName ?? session.autoLabel)
        .font(.headline)
        .lineLimit(1)

      Spacer()

      if let url = session.lastURL, !url.isEmpty {
        Text(url)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 300)
      }

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          showMetadata.toggle()
        }
      } label: {
        Image(systemName: showMetadata ? "sidebar.trailing" : "info.circle")
          .font(.body)
      }
      .buttonStyle(.plain)
      .help(showMetadata ? "Hide metadata" : "Show metadata")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift`
Expected: No warnings.

- [ ] **Step 4: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionInfoBar.swift
git commit -m "feat: add SessionInfoBar with back, status, name, and metadata toggle"
```

---

### Task 2: SessionMetadataPanel

**Files:**
- Create: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionMetadataPanel.swift`

- [ ] **Step 1: Create the metadata panel view**

```swift
import SwiftUI

struct SessionMetadataPanel: View {
  let session: SessionRecord

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        metadataSection("Browser") {
          metadataRow("URL", value: session.lastURL ?? "—", copyable: true)
          metadataRow("Title", value: session.lastTitle ?? "—", copyable: false)
          metadataRow("CDP Port", value: "\(session.cdpPort)", copyable: true)
        }

        metadataSection("Workspace") {
          metadataRow(
            "Project", value: AutoLabeler.titleCase(workspaceName: session.projectName),
            copyable: false)
          metadataRow(
            "Worktree", value: AutoLabeler.titleCase(workspaceName: session.workspaceName),
            copyable: false)
          metadataRow("Directory", value: session.workspaceDir, copyable: true)
        }

        metadataSection("Session") {
          metadataRow("ID", value: session.sessionId, copyable: true)
          metadataRow("Status", value: session.status.rawValue.capitalized, copyable: false)
          metadataRow("Created", value: relativeDate(session.createdAt), copyable: false)
          metadataRow("Last Activity", value: relativeDate(session.lastActivityAt), copyable: false)
        }
      }
      .padding(16)
    }
    .frame(width: 220)
    .background(.background.secondary)
  }

  // MARK: - Helpers

  private func metadataSection(
    _ title: String, @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      content()
    }
  }

  private func metadataRow(_ label: String, value: String, copyable: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      HStack(spacing: 4) {
        Text(value)
          .font(.caption)
          .lineLimit(2)
          .textSelection(copyable ? .enabled : .disabled)
        if copyable {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Copy to clipboard")
        }
      }
    }
  }

  private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionMetadataPanel.swift`
Expected: No warnings.

- [ ] **Step 4: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/SessionMetadataPanel.swift
git commit -m "feat: add SessionMetadataPanel with copyable metadata rows"
```

---

### Task 3: ExpandedSessionView

**Files:**
- Replace: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/ExpandedSessionView.swift`

- [ ] **Step 1: Replace the placeholder with the full implementation**

```swift
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  @AppStorage("expandedShowMetadata") private var showMetadata = true

  var body: some View {
    VStack(spacing: 0) {
      SessionInfoBar(
        session: session,
        onBack: { appState.selectedSessionId = nil },
        showMetadata: $showMetadata
      )

      Divider()

      HStack(spacing: 0) {
        screenshotArea
        if showMetadata {
          Divider()
          SessionMetadataPanel(session: session)
            .transition(.move(edge: .trailing))
        }
      }
    }
    .task(id: session.sessionId) {
      await fastRefreshLoop()
    }
  }

  // MARK: - Screenshot Area

  private var screenshotArea: some View {
    Group {
      if let data = session.lastScreenshot, let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(20)
      } else {
        VStack(spacing: 12) {
          ProgressView()
            .controlSize(.large)
          Text("Waiting for screenshot...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: - Fast Refresh

  private func fastRefreshLoop() async {
    guard session.cdpPort > 0 else { return }
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
        logger.debug("Fast refresh failed on port \(session.cdpPort): \(error.localizedDescription)")
      }

      do {
        try await Task.sleep(for: .seconds(1.5))
      } catch { break }
    }
  }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run lint**

Run: `swift-format lint --recursive PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/`
Expected: No warnings.

- [ ] **Step 4: Verify file size**

Run: `wc -l PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/ExpandedSessionView.swift`
Expected: Under 100 lines (well within 300-line CI limit).

- [ ] **Step 5: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Expanded/ExpandedSessionView.swift
git commit -m "feat: implement ExpandedSessionView with live 1.5s screenshot refresh"
```

---

### Task 4: Wire into DashboardWindow

**Files:**
- Modify: `PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/DashboardWindow.swift`

- [ ] **Step 1: Replace the placeholder in DashboardWindow**

Replace the entire content of `DashboardWindow.swift` with:

```swift
import SwiftUI

struct DashboardWindow: View {
  @Environment(AppState.self) private var appState
  @State private var selectedFilter: SidebarFilter? = .allOpen
  @State private var searchText = ""

  var body: some View {
    NavigationSplitView {
      Sidebar(selectedFilter: $selectedFilter)
        .environment(appState)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    } detail: {
      if let selectedId = appState.selectedSessionId,
        let session = appState.sessions.first(where: { $0.sessionId == selectedId })
      {
        ExpandedSessionView(session: session)
          .environment(appState)
      } else {
        SessionGrid(filter: selectedFilter, searchText: $searchText)
          .environment(appState)
      }
    }
    .frame(minWidth: 900, minHeight: 550)
  }
}
```

Key change: instead of a hardcoded placeholder, we look up the `SessionRecord` by ID and pass it to `ExpandedSessionView`. If the session isn't found (e.g. it was closed), the grid is shown.

- [ ] **Step 2: Verify it builds**

Run: `cd PlaywrightDashboard && swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Run full CI checks locally**

Run: `make qa`
Expected: lint passes, file-size passes, 19 tests pass.

- [ ] **Step 4: Commit**

```bash
git add PlaywrightDashboard/Sources/PlaywrightDashboard/Views/Dashboard/DashboardWindow.swift
git commit -m "feat: wire ExpandedSessionView into DashboardWindow detail pane"
```

---

### Task 5: Manual Smoke Test

- [ ] **Step 1: Build and launch**

Run: `cd PlaywrightDashboard && swift build && .build/debug/PlaywrightDashboard &`

- [ ] **Step 2: Open the dashboard window**

Use AppleScript or click the menubar icon → "Open Dashboard".

- [ ] **Step 3: Click a session card**

Verify:
- Info bar appears with back button, status badge, session name.
- Screenshot area shows a live screenshot (or spinner if no CDP port).
- Metadata panel is visible on the right with URL, port, workspace, timestamps.

- [ ] **Step 4: Toggle the metadata panel**

Click the ⓘ button in the info bar. Panel should animate out. Click again — panel animates back. Quit and relaunch — the preference persists.

- [ ] **Step 5: Click "Back"**

Verify the view returns to the session grid with no console errors.

- [ ] **Step 6: Kill the app**

Run: `pkill -f PlaywrightDashboard`

- [ ] **Step 7: Final commit (if any formatting needed)**

Run: `make format && make qa`
If format made changes:
```bash
git add -u
git commit -m "style: apply swift-format"
```

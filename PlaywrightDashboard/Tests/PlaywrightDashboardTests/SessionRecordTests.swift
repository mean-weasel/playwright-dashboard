import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("SessionRecord.extractProjectName")
struct ExtractProjectNameTests {

  @Test("Extracts project from .claude/worktrees/ path")
  func claudeWorktreePath() {
    let path = "/Users/dev/my-app/.claude/worktrees/fix-bug-a1b2"
    #expect(SessionRecord.extractProjectName(from: path) == "my-app")
  }

  @Test("Extracts project from .worktrees/ path")
  func dotWorktreesPath() {
    let path = "/Users/dev/my-app/.worktrees/feature-branch"
    #expect(SessionRecord.extractProjectName(from: path) == "my-app")
  }

  @Test("Falls back to last component when no worktree marker")
  func noMarker() {
    let path = "/Users/dev/my-app"
    #expect(SessionRecord.extractProjectName(from: path) == "my-app")
  }

  @Test("Uses first marker when path contains multiple")
  func multipleMarkers() {
    let path = "/Users/dev/outer/.claude/worktrees/inner/.worktrees/deep"
    #expect(SessionRecord.extractProjectName(from: path) == "outer")
  }

  @Test("Deeply nested project path")
  func deeplyNested() {
    let path = "/Users/neonwatty/code/projects/playwright-dashboard/.claude/worktrees/add-ci-9f3a"
    #expect(SessionRecord.extractProjectName(from: path) == "playwright-dashboard")
  }
}

@Suite("SessionRecord.deriveStatus")
struct DeriveStatusTests {

  @Test("nil URL returns idle")
  func nilURL() {
    #expect(SessionRecord.deriveStatus(from: nil) == .idle)
  }

  @Test("Empty string returns idle")
  func emptyURL() {
    #expect(SessionRecord.deriveStatus(from: "") == .idle)
  }

  @Test("about:blank returns idle")
  func aboutBlank() {
    #expect(SessionRecord.deriveStatus(from: "about:blank") == .idle)
  }

  @Test("Real URL returns active")
  func realURL() {
    #expect(SessionRecord.deriveStatus(from: "https://example.com") == .active)
  }

  @Test("Localhost URL returns active")
  func localhost() {
    #expect(SessionRecord.deriveStatus(from: "http://localhost:3000") == .active)
  }
}

@Suite("SessionRecord.updateFromScreenshot")
struct ScreenshotUpdateTests {

  @Test("does not revive a closed session")
  func closedSessionIgnoresScreenshotUpdate() {
    let session = SessionRecord(
      sessionId: "closed-session",
      autoLabel: "Closed",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      status: .closed
    )
    let result = CDPClient.ScreenshotResult(
      jpeg: Data([0x01, 0x02]),
      url: "http://localhost:3000",
      title: "App"
    )

    session.updateFromScreenshot(result)

    #expect(session.status == .closed)
    #expect(session.lastScreenshot == nil)
    #expect(session.lastURL == nil)
    #expect(session.lastTitle == nil)
  }

  @Test("unchanged active screenshot metadata refreshes activity")
  func unchangedActiveScreenshotRefreshesActivity() {
    let oldActivity = Date().addingTimeInterval(-600)
    let session = SessionRecord(
      sessionId: "idle-session",
      autoLabel: "Idle",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      status: .active,
      lastURL: "http://localhost:3000",
      lastTitle: "App",
      lastActivityAt: oldActivity
    )
    let result = CDPClient.ScreenshotResult(
      jpeg: Data([0x01, 0x02]),
      url: "http://localhost:3000",
      title: "App"
    )

    session.updateFromScreenshot(result)

    #expect(session.lastActivityAt > oldActivity)
    #expect(session.lastScreenshot == Data([0x01, 0x02]))
    #expect(session.status == .active)
  }

  @Test("unchanged idle screenshot metadata does not refresh activity")
  func unchangedIdleScreenshotDoesNotRefreshActivity() {
    let oldActivity = Date().addingTimeInterval(-600)
    let session = SessionRecord(
      sessionId: "idle-session",
      autoLabel: "Idle",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      status: .idle,
      lastURL: "about:blank",
      lastTitle: "",
      lastActivityAt: oldActivity
    )
    let result = CDPClient.ScreenshotResult(
      jpeg: Data([0x01, 0x02]),
      url: "about:blank",
      title: ""
    )

    session.updateFromScreenshot(result)

    #expect(session.lastActivityAt == oldActivity)
    #expect(session.lastScreenshot == Data([0x01, 0x02]))
    #expect(session.status == .idle)
  }

  @Test("changed screenshot metadata refreshes activity")
  func changedScreenshotRefreshesActivity() {
    let oldActivity = Date().addingTimeInterval(-600)
    let session = SessionRecord(
      sessionId: "active-session",
      autoLabel: "Active",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      status: .idle,
      lastURL: "about:blank",
      lastTitle: "",
      lastActivityAt: oldActivity
    )
    let result = CDPClient.ScreenshotResult(
      jpeg: Data([0x01, 0x02]),
      url: "http://localhost:3000",
      title: "App"
    )

    session.updateFromScreenshot(result)

    #expect(session.lastActivityAt > oldActivity)
    #expect(session.status == .active)
  }

  @Test("screenshot update retains page targets and selected target")
  func screenshotUpdateRetainsPageTargetsAndSelection() {
    let targets = [
      CDPPageTarget(
        id: "first",
        type: "page",
        url: "http://localhost:3000",
        title: "First",
        webSocketDebuggerUrl: "ws://localhost/devtools/page/first"
      ),
      CDPPageTarget(
        id: "second",
        type: "page",
        url: "http://localhost:3001",
        title: "Second",
        webSocketDebuggerUrl: "ws://localhost/devtools/page/second"
      ),
    ]
    let session = SessionRecord(
      sessionId: "active-session",
      autoLabel: "Active",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock"
    )

    session.updateFromScreenshot(
      CDPClient.ScreenshotResult(
        jpeg: Data([0x01]),
        url: targets[1].url,
        title: targets[1].title,
        targetId: targets[1].id,
        pageTargets: targets
      )
    )

    #expect(session.pageTargets == targets)
    #expect(session.selectedTargetId == "second")
    #expect(session.selectedPageTarget?.title == "Second")
  }

  @Test("screencast frame without target list does not clear refreshed targets")
  func screencastFrameWithoutTargetsDoesNotClearRefreshedTargets() {
    let targets = [
      CDPPageTarget(
        id: "app",
        type: "page",
        url: "http://localhost:3000",
        title: "App",
        webSocketDebuggerUrl: "ws://localhost/devtools/page/app"
      )
    ]
    let session = SessionRecord(
      sessionId: "active-session",
      autoLabel: "Active",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      pageTargets: targets,
      selectedTargetId: "app"
    )

    session.updateFromScreenshot(
      CDPClient.ScreenshotResult(
        jpeg: Data([0x01]),
        url: "http://localhost:3000",
        title: "App",
        targetId: "app"
      )
    )

    #expect(session.pageTargets == targets)
    #expect(session.selectedTargetId == "app")
  }
}

@Suite("CDPPageTarget")
struct CDPPageTargetTests {
  @Test("devToolsFrontendURL builds target-specific inspector URL")
  func devToolsFrontendURLBuildsTargetSpecificURL() {
    let target = CDPPageTarget(
      id: "page-1",
      type: "page",
      url: "https://example.com",
      title: "Example",
      webSocketDebuggerUrl: "ws://localhost:9333/devtools/page/page-1"
    )

    #expect(
      target.devToolsFrontendURL(port: 9333)?.absoluteString
        == "http://localhost:9333/devtools/inspector.html?ws=localhost:9333/devtools/page/page-1"
    )
  }

  @Test("devToolsFrontendURL returns nil without usable target id")
  func devToolsFrontendURLReturnsNilWithoutUsableTargetId() {
    let target = CDPPageTarget(
      id: " ",
      type: "page",
      url: "https://example.com",
      title: "Example",
      webSocketDebuggerUrl: "ws://localhost:9333/devtools/page/blank"
    )

    #expect(target.devToolsFrontendURL(port: 9333) == nil)
    #expect(target.devToolsFrontendURL(port: 0) == nil)
  }
}

@Suite("SessionRecord target selection")
struct SessionRecordTargetSelectionTests {
  @Test("selectPageTarget preserves valid choice")
  func selectPageTargetPreservesValidChoice() {
    let session = makeSession()
    session.pageTargets = makeTargets()

    session.selectPageTarget(id: "second")

    #expect(session.selectedTargetId == "second")
    #expect(session.selectedPageTarget?.id == "second")
  }

  @Test("selectPageTarget falls back when requested target is missing")
  func selectPageTargetFallsBackWhenRequestedTargetIsMissing() {
    let session = makeSession()
    session.pageTargets = makeTargets()

    session.selectPageTarget(id: "missing")

    #expect(session.selectedTargetId == "first")
    #expect(session.selectedPageTarget?.id == "first")
  }

  @Test("page target refresh keeps existing selection when target remains")
  func pageTargetRefreshKeepsExistingSelection() {
    let session = makeSession()
    session.pageTargets = makeTargets()
    session.selectPageTarget(id: "second")

    session.pageTargets = [
      makeTarget(id: "second", url: "http://localhost:3001", title: "Second"),
      makeTarget(id: "third", url: "http://localhost:3002", title: "Third"),
    ]

    #expect(session.selectedTargetId == "second")
  }

  @Test("page target refresh falls back when selected target disappears")
  func pageTargetRefreshFallsBackWhenSelectedTargetDisappears() {
    let session = makeSession()
    session.pageTargets = makeTargets()
    session.selectPageTarget(id: "second")

    session.pageTargets = [
      makeTarget(id: "third", url: "http://localhost:3002", title: "Third")
    ]

    #expect(session.selectedTargetId == "third")
  }

  @Test("updatePageTargets reports whether targets or selection changed")
  func updatePageTargetsReportsChanges() {
    let session = makeSession()

    #expect(session.updatePageTargets(makeTargets()))
    #expect(!session.updatePageTargets(makeTargets()))

    session.selectPageTarget(id: "second")

    #expect(
      session.updatePageTargets([
        makeTarget(id: "third", url: "http://localhost:3002", title: "Third")
      ])
    )
    #expect(session.selectedTargetId == "third")
  }

  private func makeSession() -> SessionRecord {
    SessionRecord(
      sessionId: UUID().uuidString,
      autoLabel: "Session",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock"
    )
  }

  private func makeTargets() -> [CDPPageTarget] {
    [
      makeTarget(id: "blank", url: "about:blank", title: ""),
      makeTarget(id: "first", url: "http://localhost:3000", title: "First"),
      makeTarget(id: "second", url: "http://localhost:3001", title: "Second"),
    ]
  }

  private func makeTarget(id: String, url: String, title: String) -> CDPPageTarget {
    CDPPageTarget(
      id: id,
      type: "page",
      url: url,
      title: title,
      webSocketDebuggerUrl: "ws://localhost/devtools/page/\(id)"
    )
  }
}

@Suite("SessionRecord.markStaleIfInactive")
struct MarkStaleIfInactiveTests {

  @Test("active session older than threshold becomes stale")
  func oldActiveSessionBecomesStale() {
    let now = Date()
    let session = makeSession(
      status: .active,
      lastActivityAt: now.addingTimeInterval(-301)
    )

    let didMarkStale = session.markStaleIfInactive(threshold: 300, now: now)

    #expect(didMarkStale)
    #expect(session.status == .stale)
  }

  @Test("idle session older than threshold becomes stale")
  func oldIdleSessionBecomesStale() {
    let now = Date()
    let session = makeSession(
      status: .idle,
      lastActivityAt: now.addingTimeInterval(-301)
    )

    let didMarkStale = session.markStaleIfInactive(threshold: 300, now: now)

    #expect(didMarkStale)
    #expect(session.status == .stale)
  }

  @Test("recent activity remains current")
  func recentActivityDoesNotBecomeStale() {
    let now = Date()
    let session = makeSession(
      status: .active,
      lastActivityAt: now.addingTimeInterval(-299)
    )

    let didMarkStale = session.markStaleIfInactive(threshold: 300, now: now)

    #expect(!didMarkStale)
    #expect(session.status == .active)
  }

  @Test("disabled threshold leaves session unchanged")
  func disabledThresholdDoesNotMarkStale() {
    let now = Date()
    let session = makeSession(
      status: .active,
      lastActivityAt: now.addingTimeInterval(-3_600)
    )

    let didMarkStale = session.markStaleIfInactive(threshold: 0, now: now)

    #expect(!didMarkStale)
    #expect(session.status == .active)
  }

  @Test("terminal and pending-close statuses are not overwritten")
  func protectedStatusesDoNotBecomeStale() {
    let now = Date()
    let statuses: [SessionStatus] = [.stale, .closing, .closeFailed, .closed]

    for status in statuses {
      let session = makeSession(
        status: status,
        lastActivityAt: now.addingTimeInterval(-3_600)
      )

      let didMarkStale = session.markStaleIfInactive(threshold: 300, now: now)

      #expect(!didMarkStale)
      #expect(session.status == status)
    }
  }

  private func makeSession(
    status: SessionStatus,
    lastActivityAt: Date
  ) -> SessionRecord {
    SessionRecord(
      sessionId: UUID().uuidString,
      autoLabel: "Session",
      workspaceDir: "/tmp/app",
      cdpPort: 9222,
      socketPath: "/tmp/app.sock",
      status: status,
      lastActivityAt: lastActivityAt
    )
  }
}

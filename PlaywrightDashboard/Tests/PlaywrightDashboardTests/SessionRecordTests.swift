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

  @Test("unchanged screenshot metadata does not refresh activity")
  func unchangedScreenshotDoesNotRefreshActivity() {
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

    #expect(session.lastActivityAt == oldActivity)
    #expect(session.lastScreenshot == Data([0x01, 0x02]))
    #expect(session.status == .active)
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

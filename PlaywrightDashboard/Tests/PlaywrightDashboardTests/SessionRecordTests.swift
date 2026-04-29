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
}

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

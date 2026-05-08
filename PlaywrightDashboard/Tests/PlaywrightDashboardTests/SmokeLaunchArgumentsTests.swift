import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("SmokeLaunchArguments")
struct SmokeLaunchArgumentsTests {

  @Test("parses smoke launch flags")
  func parsesSmokeLaunchFlags() {
    let arguments = SmokeLaunchArguments(arguments: [
      "PlaywrightDashboard",
      "--smoke-in-memory-store",
      "--smoke-open-dashboard",
      "--smoke-open-settings",
      "--smoke-force-snapshot-fallback",
      "--smoke-safe-mode",
      "--smoke-disable-screenshots",
      "--smoke-dashboard-filter-closed",
      "--smoke-daemon-dir",
      "/tmp/playwright-dashboard-daemon",
      "--smoke-session-id",
      "visual-expanded",
      "--smoke-recording-export-result",
      "/tmp/playwright-dashboard-recording/result.json",
    ])

    #expect(arguments.usesInMemoryStore)
    #expect(arguments.opensDashboard)
    #expect(arguments.opensSettings)
    #expect(arguments.forcesSnapshotFallback)
    #expect(arguments.enablesSafeMode)
    #expect(arguments.disablesScreenshots)
    #expect(arguments.dashboardFilter == .closed)
    #expect(arguments.daemonDirectory?.path == "/tmp/playwright-dashboard-daemon")
    #expect(arguments.selectedSessionId == "visual-expanded")
    #expect(
      arguments.recordingExportResultURL?.path
        == "/tmp/playwright-dashboard-recording/result.json")
  }

  @Test("uses production defaults when smoke flags are absent")
  func usesDefaultsWhenSmokeFlagsAreAbsent() {
    let arguments = SmokeLaunchArguments(arguments: ["PlaywrightDashboard"])

    #expect(!arguments.usesInMemoryStore)
    #expect(!arguments.opensDashboard)
    #expect(!arguments.opensSettings)
    #expect(!arguments.forcesSnapshotFallback)
    #expect(!arguments.enablesSafeMode)
    #expect(!arguments.disablesScreenshots)
    #expect(arguments.dashboardFilter == .allOpen)
    #expect(arguments.daemonDirectory == nil)
    #expect(arguments.selectedSessionId == nil)
    #expect(arguments.recordingExportResultURL == nil)
  }

  @Test("ignores smoke flags that are missing values")
  func ignoresFlagsMissingValues() {
    let arguments = SmokeLaunchArguments(arguments: [
      "PlaywrightDashboard",
      "--smoke-daemon-dir",
      "--smoke-session-id",
    ])

    #expect(arguments.daemonDirectory == nil)
    #expect(arguments.selectedSessionId == nil)
  }
}

import Foundation

struct SmokeLaunchArguments {
  let usesInMemoryStore: Bool
  let opensDashboard: Bool
  let opensSettings: Bool
  let snapshotFallbackOverride: Bool?
  let safeModeOverride: Bool?
  let disablesScreenshots: Bool
  let dashboardFilter: SidebarFilter?
  let daemonDirectory: URL?
  let selectedSessionId: String?
  let recordingExportResultURL: URL?
  let readinessDirectory: URL?
  let navigationURL: String?
  let renameSessionId: String?
  let renameTo: String?
  let markSessionClosedId: String?
  let reorderSourceId: String?
  let reorderTargetId: String?
  let persistentStorePath: URL?
  let closeSessionId: String?
  let markSessionStaleId: String?
  let cleanupStaleSessions: Bool
  let searchQuery: String?

  init(arguments: [String]) {
    self.usesInMemoryStore = arguments.contains("--smoke-in-memory-store")
    self.opensDashboard = arguments.contains("--smoke-open-dashboard")
    self.opensSettings = arguments.contains("--smoke-open-settings")
    self.snapshotFallbackOverride =
      arguments.contains("--smoke-force-snapshot-fallback") ? true : nil
    self.safeModeOverride =
      if arguments.contains("--smoke-safe-mode") {
        true
      } else if arguments.contains("--smoke-disable-safe-mode") {
        false
      } else {
        nil
      }
    self.disablesScreenshots = arguments.contains("--smoke-disable-screenshots")
    self.dashboardFilter =
      arguments.contains("--smoke-dashboard-filter-closed") ? .closed : .allOpen
    self.daemonDirectory = Self.urlArgument(
      named: "--smoke-daemon-dir", arguments: arguments)
    self.selectedSessionId = Self.stringArgument(
      named: "--smoke-session-id", arguments: arguments)
    self.recordingExportResultURL = Self.fileURLArgument(
      named: "--smoke-recording-export-result", arguments: arguments)
    self.readinessDirectory = Self.urlArgument(
      named: "--smoke-readiness-dir", arguments: arguments)
    self.navigationURL = Self.stringArgument(
      named: "--smoke-navigate-url", arguments: arguments)
    self.renameSessionId = Self.stringArgument(
      named: "--smoke-rename-session-id", arguments: arguments)
    self.renameTo = Self.stringArgument(
      named: "--smoke-rename-to", arguments: arguments)
    self.markSessionClosedId = Self.stringArgument(
      named: "--smoke-mark-session-closed-id", arguments: arguments)
    self.reorderSourceId = Self.stringArgument(
      named: "--smoke-reorder-source-id", arguments: arguments)
    self.reorderTargetId = Self.stringArgument(
      named: "--smoke-reorder-target-id", arguments: arguments)
    self.persistentStorePath = Self.urlArgument(
      named: "--smoke-persistent-store-path", arguments: arguments)
    self.closeSessionId = Self.stringArgument(
      named: "--smoke-close-session-id", arguments: arguments)
    self.markSessionStaleId = Self.stringArgument(
      named: "--smoke-mark-session-stale-id", arguments: arguments)
    self.cleanupStaleSessions = arguments.contains("--smoke-cleanup-stale-sessions")
    self.searchQuery = Self.stringArgument(
      named: "--smoke-search-query", arguments: arguments)
  }

  private static func stringArgument(named flag: String, arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
      arguments.indices.contains(index + 1)
    else {
      return nil
    }
    let value = arguments[index + 1]
    return value.hasPrefix("--") ? nil : value
  }

  private static func urlArgument(named flag: String, arguments: [String]) -> URL? {
    guard let value = stringArgument(named: flag, arguments: arguments) else { return nil }
    return URL(fileURLWithPath: value, isDirectory: true)
  }

  private static func fileURLArgument(named flag: String, arguments: [String]) -> URL? {
    guard let value = stringArgument(named: flag, arguments: arguments) else { return nil }
    return URL(fileURLWithPath: value, isDirectory: false)
  }
}

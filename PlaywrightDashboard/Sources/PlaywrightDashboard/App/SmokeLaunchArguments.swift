import Foundation

struct SmokeLaunchArguments {
  let usesInMemoryStore: Bool
  let opensDashboard: Bool
  let opensSettings: Bool
  let forcesSnapshotFallback: Bool
  let disablesScreenshots: Bool
  let dashboardFilter: SidebarFilter?
  let daemonDirectory: URL?
  let selectedSessionId: String?
  let recordingExportResultURL: URL?

  init(arguments: [String]) {
    self.usesInMemoryStore = arguments.contains("--smoke-in-memory-store")
    self.opensDashboard = arguments.contains("--smoke-open-dashboard")
    self.opensSettings = arguments.contains("--smoke-open-settings")
    self.forcesSnapshotFallback = arguments.contains("--smoke-force-snapshot-fallback")
    self.disablesScreenshots = arguments.contains("--smoke-disable-screenshots")
    self.dashboardFilter =
      arguments.contains("--smoke-dashboard-filter-closed") ? .closed : .allOpen
    self.daemonDirectory = Self.urlArgument(
      named: "--smoke-daemon-dir", arguments: arguments)
    self.selectedSessionId = Self.stringArgument(
      named: "--smoke-session-id", arguments: arguments)
    self.recordingExportResultURL = Self.fileURLArgument(
      named: "--smoke-recording-export-result", arguments: arguments)
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

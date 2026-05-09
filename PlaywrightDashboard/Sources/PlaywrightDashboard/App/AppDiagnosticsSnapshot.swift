import Foundation

struct AppDiagnosticsSnapshot: Equatable {
  struct SessionSummary: Equatable {
    let sessionId: String
    let status: String
    let workspaceDir: String
    let cdpPort: Int
    let url: String?
    let title: String?
    let targetCount: Int
  }

  let generatedAt: Date
  let appVersion: String
  let appBuild: String
  let bundleIdentifier: String
  let operatingSystem: String
  let safeModeEnabled: Bool
  let persistenceDegraded: Bool
  let persistenceError: String?
  let playwrightCLIStatus: String
  let daemonDirectory: String
  let sessionFileCount: Int
  let sessionCounts: [String: Int]
  let sessionFileErrors: [String: String]
  let terminationErrors: [String: String]
  let lastPersistenceSaveError: String?
  let lastScreenshotSaveError: String?
  let lastOpenURLError: String?
  let activeScreenshotClients: Int
  let screenshotBackoffPorts: Int
  let screenshotCaptureFailures: Int
  let screenshotBackoffSkips: Int
  let sessions: [SessionSummary]

  var text: String {
    var lines: [String] = [
      "Playwright Dashboard Diagnostics",
      "generatedAt: \(Self.formattedDate(generatedAt))",
      "appVersion: \(appVersion)",
      "appBuild: \(appBuild)",
      "bundleIdentifier: \(bundleIdentifier)",
      "operatingSystem: \(operatingSystem)",
      "safeModeEnabled: \(safeModeEnabled)",
      "persistenceDegraded: \(persistenceDegraded)",
      "persistenceError: \(persistenceError ?? "none")",
      "playwrightCLIStatus: \(playwrightCLIStatus)",
      "daemonDirectory: \(daemonDirectory)",
      "sessionFileCount: \(sessionFileCount)",
      "lastPersistenceSaveError: \(lastPersistenceSaveError ?? "none")",
      "lastScreenshotSaveError: \(lastScreenshotSaveError ?? "none")",
      "lastOpenURLError: \(lastOpenURLError ?? "none")",
      "activeScreenshotClients: \(activeScreenshotClients)",
      "screenshotBackoffPorts: \(screenshotBackoffPorts)",
      "screenshotCaptureFailures: \(screenshotCaptureFailures)",
      "screenshotBackoffSkips: \(screenshotBackoffSkips)",
      "",
      "Session Counts",
    ]

    for key in sessionCounts.keys.sorted() {
      lines.append("\(key): \(sessionCounts[key] ?? 0)")
    }

    lines.append("")
    lines.append("Session File Errors")
    Self.appendDictionary(sessionFileErrors, to: &lines)

    lines.append("")
    lines.append("Termination Errors")
    Self.appendDictionary(terminationErrors, to: &lines)

    lines.append("")
    lines.append("Sessions")
    if sessions.isEmpty {
      lines.append("none")
    } else {
      for session in sessions.sorted(by: { $0.sessionId < $1.sessionId }) {
        lines.append("- sessionId: \(session.sessionId)")
        lines.append("  status: \(session.status)")
        lines.append("  workspaceDir: \(session.workspaceDir)")
        lines.append("  cdpPort: \(session.cdpPort)")
        lines.append("  url: \(session.url ?? "none")")
        lines.append("  title: \(session.title ?? "none")")
        lines.append("  targetCount: \(session.targetCount)")
      }
    }

    lines.append("")
    lines.append("Privacy")
    lines.append("Includes developer metadata, local paths, ports, URLs, settings, and errors.")
    lines.append("Excludes screenshots, cookies, page content, and recording files.")

    return lines.joined(separator: "\n")
  }

  static func formattedDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func appendDictionary(_ dictionary: [String: String], to lines: inout [String]) {
    guard !dictionary.isEmpty else {
      lines.append("none")
      return
    }

    for key in dictionary.keys.sorted() {
      lines.append("\(key): \(dictionary[key] ?? "")")
    }
  }
}

import AppKit
import Foundation

extension AppState {
  func setPersistenceDegraded(_ isDegraded: Bool, reason: String? = nil) {
    isPersistenceDegraded = isDegraded
    persistenceDegradedReason = isDegraded ? reason : nil
  }

  func dismissPersistenceSaveError() {
    lastPersistenceSaveError = nil
  }

  var daemonDirectoryPath: String {
    daemonDirectory.path
  }

  var setupCommandText: String {
    "playwright-cli -s=dashboard-demo open https://example.com --browser=chrome --headed"
  }

  var applicationSupportDirectory: URL {
    let baseURL =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )
      .first ?? FileManager.default.homeDirectoryForCurrentUser
    let bundleName = Bundle.main.bundleIdentifier ?? "PlaywrightDashboard"
    return baseURL.appendingPathComponent(bundleName, isDirectory: true)
  }

  func makeDiagnosticsSnapshot(now: Date = Date()) -> AppDiagnosticsSnapshot {
    let sessionCounts = Dictionary(grouping: sessions, by: { $0.status.rawValue })
      .mapValues(\.count)
    let sessionSummaries = sessions.map {
      AppDiagnosticsSnapshot.SessionSummary(
        sessionId: $0.sessionId,
        status: $0.status.rawValue,
        workspaceDir: $0.workspaceDir,
        cdpPort: $0.cdpPort,
        url: $0.lastURL,
        title: $0.lastTitle,
        targetCount: $0.pageTargets.count
      )
    }

    return AppDiagnosticsSnapshot(
      generatedAt: now,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "unknown",
      appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      safeModeEnabled: isSafeMode,
      persistenceDegraded: isPersistenceDegraded,
      persistenceError: persistenceDegradedReason,
      playwrightCLIStatus: playwrightCLIStatus.displayText,
      daemonDirectory: daemonDirectory.path,
      sessionFileCount: sessionFileProvider().count,
      sessionCounts: sessionCounts,
      sessionFileErrors: sessionFileErrors,
      terminationErrors: sessionTerminationErrors,
      lastPersistenceSaveError: lastPersistenceSaveError,
      lastScreenshotSaveError: lastScreenshotSaveError,
      lastOpenURLError: lastOpenURLError,
      activeScreenshotClients: screenshotService.activeClientCount,
      screenshotBackoffPorts: screenshotService.backoffPortCount,
      screenshotCaptureFailures: screenshotService.captureFailureCount,
      screenshotBackoffSkips: screenshotService.skippedForBackoffCount,
      sessions: sessionSummaries
    )
  }

  func diagnosticsText() -> String {
    makeDiagnosticsSnapshot().text
  }

  func copyAppDiagnostics() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(diagnosticsText(), forType: .string)
  }

  @discardableResult
  func exportAppDiagnostics(to url: URL) -> Bool {
    do {
      try diagnosticsText().write(to: url, atomically: true, encoding: .utf8)
      lastDiagnosticsExportURL = url
      lastDiagnosticsExportError = nil
      return true
    } catch {
      lastDiagnosticsExportError = error.localizedDescription
      return false
    }
  }

  func revealApplicationSupportDirectory() {
    try? FileManager.default.createDirectory(
      at: applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    NSWorkspace.shared.activateFileViewerSelecting([applicationSupportDirectory])
  }
}

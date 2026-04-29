import AppKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppState {
  private(set) var sessions: [SessionRecord] = []
  var isPopoverOpen: Bool = false
  var isDashboardOpen: Bool = false
  var selectedSessionId: String?
  private(set) var sessionTerminationErrors: [String: String] = [:]
  private(set) var lastSavedScreenshotURL: URL?

  // Services
  private let sessionFileProvider: @MainActor () -> [URL]
  private let startWatching: @MainActor () -> Void
  private let stopWatching: @MainActor () -> Void
  private let shouldStartScreenshots: Bool
  private let syncInterval: Duration
  private let sessionTerminator: SessionTerminator
  private let screenshotDirectoryProvider: @MainActor () -> URL
  private var sessionManager: SessionManager?
  private let screenshotService = ScreenshotService()
  private var syncTask: Task<Void, Never>?
  private var modelContext: ModelContext?

  init() {
    let watcher = DaemonWatcher()
    self.sessionFileProvider = { watcher.sessionFiles }
    self.startWatching = { watcher.start() }
    self.stopWatching = { watcher.stop() }
    self.shouldStartScreenshots = true
    self.syncInterval = .seconds(2)
    self.sessionTerminator = SessionTerminator()
    self.screenshotDirectoryProvider = Self.defaultScreenshotDirectory
  }

  init(
    sessionFileProvider: @escaping @MainActor () -> [URL],
    startWatching: @escaping @MainActor () -> Void = {},
    stopWatching: @escaping @MainActor () -> Void = {},
    shouldStartScreenshots: Bool = false,
    syncInterval: Duration = .seconds(2),
    sessionTerminator: SessionTerminator = SessionTerminator(),
    screenshotDirectoryProvider: @escaping @MainActor () -> URL =
      AppState.defaultScreenshotDirectory
  ) {
    self.sessionFileProvider = sessionFileProvider
    self.startWatching = startWatching
    self.stopWatching = stopWatching
    self.shouldStartScreenshots = shouldStartScreenshots
    self.syncInterval = syncInterval
    self.sessionTerminator = sessionTerminator
    self.screenshotDirectoryProvider = screenshotDirectoryProvider
  }

  /// Call once from a view that has access to the ModelContext.
  func startSync(modelContext: ModelContext) {
    guard sessionManager == nil else { return }

    let manager = SessionManager(
      sessionFileProvider: sessionFileProvider, modelContext: modelContext)
    self.sessionManager = manager
    self.modelContext = modelContext

    // Start watching the filesystem
    startWatching()
    performSync()
    if shouldStartScreenshots {
      screenshotService.start(appState: self)
    }

    // Kick off a periodic sync loop that reconciles watcher → SwiftData → sessions
    syncTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          guard let self else { return }
          try await Task.sleep(for: self.syncInterval)
        } catch { break }
        guard let self else { return }
        self.performSync()
      }
    }
  }

  /// Cancel the sync loop and stop all services.
  func stopSync() {
    syncTask?.cancel()
    syncTask = nil
    sessionManager = nil
    modelContext = nil
    screenshotService.stop()
    stopWatching()
  }

  func rename(_ session: SessionRecord, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    session.customName = trimmed.isEmpty ? nil : trimmed
    saveSessionChanges()
  }

  func close(_ session: SessionRecord, byUser: Bool = true) {
    if selectedSessionId == session.sessionId {
      selectedSessionId = nil
    }
    session.close(byUser: byUser)
    saveSessionChanges()
  }

  func closeAndTerminate(_ session: SessionRecord) {
    close(session, byUser: true)
    Task {
      do {
        try await sessionTerminator.close(sessionId: session.sessionId)
        sessionTerminationErrors[session.sessionId] = nil
      } catch {
        sessionTerminationErrors[session.sessionId] = error.localizedDescription
      }
    }
  }

  func reopen(_ session: SessionRecord) {
    session.reopen()
    saveSessionChanges()
  }

  func closeStaleSessions() {
    var didCloseSelectedSession = false
    for session in sessions where session.status == .stale {
      didCloseSelectedSession = didCloseSelectedSession || selectedSessionId == session.sessionId
      session.close(byUser: true)
    }
    if didCloseSelectedSession {
      selectedSessionId = nil
    }
    saveSessionChanges()
  }

  func closeAndTerminateStaleSessions() {
    let staleSessions = sessions.filter { $0.status == .stale }
    closeStaleSessions()
    for session in staleSessions {
      Task {
        do {
          try await sessionTerminator.close(sessionId: session.sessionId)
          sessionTerminationErrors[session.sessionId] = nil
        } catch {
          sessionTerminationErrors[session.sessionId] = error.localizedDescription
        }
      }
    }
  }

  func clearClosedSessions() {
    guard let modelContext else {
      sessions.removeAll { $0.status == .closed }
      return
    }

    for session in sessions where session.status == .closed {
      modelContext.delete(session)
    }
    sessions.removeAll { $0.status == .closed }
    saveSessionChanges()
  }

  func saveScreenshot(_ session: SessionRecord) -> URL? {
    guard let data = session.lastScreenshot else { return nil }
    let downloads = screenshotDirectoryProvider()
    let filename = "\(session.sessionId)-\(Self.filenameTimestamp()).jpg"
    let url = downloads.appendingPathComponent(filename)

    do {
      try data.write(to: url, options: .atomic)
      lastSavedScreenshotURL = url
      return url
    } catch {
      return nil
    }
  }

  func openCurrentURL(_ session: SessionRecord) {
    guard let urlString = session.lastURL,
      let url = URL(string: urlString),
      ["http", "https"].contains(url.scheme?.lowercased())
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  func openCDPInspector(_ session: SessionRecord) {
    guard session.cdpPort > 0,
      let url = URL(string: "http://localhost:\(session.cdpPort)")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  func reorder(sourceId: String, targetId: String) -> Bool {
    guard sourceId != targetId else { return false }
    guard let source = sessions.first(where: { $0.sessionId == sourceId }),
      let target = sessions.first(where: { $0.sessionId == targetId })
    else { return false }

    let temp = source.gridOrder
    source.gridOrder = target.gridOrder
    target.gridOrder = temp
    saveSessionChanges()
    return true
  }

  func saveSessionChanges() {
    persistSessionChanges()
  }

  private func performSync() {
    guard let manager = sessionManager else { return }
    manager.syncWithWatcher()
    sessions = manager.allSessions
  }

  private func persistSessionChanges() {
    do {
      try modelContext?.save()
    } catch {
      modelContext?.rollback()
      performSync()
    }
  }

  private static func filenameTimestamp(date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: ".", with: "-")
  }

  private static func defaultScreenshotDirectory() -> URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }
}

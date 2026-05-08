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
  private(set) var sessionFileErrors: [String: String] = [:]
  var lastSavedScreenshotURL: URL?
  var lastScreenshotSaveError: String?
  var lastOpenURLError: String?
  private(set) var lastPersistenceSaveError: String?
  private(set) var playwrightCLIStatus: PlaywrightCLIStatus = .unknown
  private(set) var isPersistenceDegraded = false
  private let sessionFileProvider: @MainActor () -> [URL]
  private let startWatching: @MainActor () -> Void
  private let stopWatching: @MainActor () -> Void
  private let shouldStartScreenshots: Bool
  private let syncInterval: Duration
  private let sessionTerminator: SessionTerminator
  private let cliStatusProvider: PlaywrightCLIStatusProvider
  private let safeModeProvider: @MainActor () -> Bool
  let screenshotDirectoryProvider: @MainActor () -> URL
  let urlOpener: @MainActor (URL) -> Bool
  private let modelContextSaver: @MainActor (ModelContext?) throws -> Void
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
    self.cliStatusProvider = PlaywrightCLIStatusProvider()
    self.safeModeProvider = { DashboardSettings.safeMode() }
    self.screenshotDirectoryProvider = Self.defaultScreenshotDirectory
    self.urlOpener = { NSWorkspace.shared.open($0) }
    self.modelContextSaver = Self.defaultModelContextSaver
  }
  init(daemonDirectory: URL, shouldStartScreenshots: Bool = true) {
    let watcher = DaemonWatcher(daemonDirectory: daemonDirectory)
    self.sessionFileProvider = { watcher.sessionFiles }
    self.startWatching = { watcher.start() }
    self.stopWatching = { watcher.stop() }
    self.shouldStartScreenshots = shouldStartScreenshots
    self.syncInterval = .seconds(2)
    self.sessionTerminator = SessionTerminator()
    self.cliStatusProvider = PlaywrightCLIStatusProvider()
    self.safeModeProvider = { DashboardSettings.safeMode() }
    self.screenshotDirectoryProvider = Self.defaultScreenshotDirectory
    self.urlOpener = { NSWorkspace.shared.open($0) }
    self.modelContextSaver = Self.defaultModelContextSaver
  }
  init(
    sessionFileProvider: @escaping @MainActor () -> [URL],
    startWatching: @escaping @MainActor () -> Void = {},
    stopWatching: @escaping @MainActor () -> Void = {},
    shouldStartScreenshots: Bool = false,
    syncInterval: Duration = .seconds(2),
    sessionTerminator: SessionTerminator = SessionTerminator(),
    cliStatusProvider: PlaywrightCLIStatusProvider = PlaywrightCLIStatusProvider(),
    safeModeProvider: @escaping @MainActor () -> Bool = { DashboardSettings.safeMode() },
    screenshotDirectoryProvider: @escaping @MainActor () -> URL =
      AppState.defaultScreenshotDirectory,
    urlOpener: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
    modelContextSaver: @escaping @MainActor (ModelContext?) throws -> Void =
      AppState.defaultModelContextSaver
  ) {
    self.sessionFileProvider = sessionFileProvider
    self.startWatching = startWatching
    self.stopWatching = stopWatching
    self.shouldStartScreenshots = shouldStartScreenshots
    self.syncInterval = syncInterval
    self.sessionTerminator = sessionTerminator
    self.cliStatusProvider = cliStatusProvider
    self.safeModeProvider = safeModeProvider
    self.screenshotDirectoryProvider = screenshotDirectoryProvider
    self.urlOpener = urlOpener
    self.modelContextSaver = modelContextSaver
  }

  var isSafeMode: Bool {
    safeModeProvider()
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
    guard !isSafeMode else { return }
    if selectedSessionId == session.sessionId {
      selectedSessionId = nil
    }
    session.close(byUser: byUser)
    saveSessionChanges()
  }

  func closeAndTerminate(_ session: SessionRecord) {
    guard !isSafeMode else { return }
    beginTerminating(session)
    Task {
      await terminate(session)
    }
  }

  func retryTerminate(_ session: SessionRecord) {
    guard !isSafeMode else { return }
    beginTerminating(session)
    Task {
      await terminate(session)
    }
  }

  func reopen(_ session: SessionRecord) {
    session.reopen()
    saveSessionChanges()
  }

  func closeStaleSessions() {
    guard !isSafeMode else { return }
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
    guard !isSafeMode else { return }
    let staleSessions = sessions.filter { $0.status == .stale }
    closeStaleSessions()
    for session in staleSessions {
      Task {
        await terminate(session)
      }
    }
  }

  func dismissTerminationError(sessionId: String) {
    sessionTerminationErrors[sessionId] = nil
    if let session = sessions.first(where: { $0.sessionId == sessionId }),
      session.status == .closeFailed
    {
      session.status = SessionRecord.deriveStatus(from: session.lastURL)
      saveSessionChanges()
    }
  }

  func dismissAllTerminationErrors() {
    for session in sessions where session.status == .closeFailed {
      session.status = SessionRecord.deriveStatus(from: session.lastURL)
    }
    sessionTerminationErrors.removeAll()
    saveSessionChanges()
  }

  func dismissSessionFileError(filename: String) {
    sessionFileErrors[filename] = nil
  }

  func dismissAllSessionFileErrors() {
    sessionFileErrors.removeAll()
  }

  func refreshPlaywrightCLIStatus() {
    Task {
      playwrightCLIStatus = await cliStatusProvider.status()
    }
  }

  func setPersistenceDegraded(_ isDegraded: Bool) {
    isPersistenceDegraded = isDegraded
  }

  func dismissPersistenceSaveError() {
    lastPersistenceSaveError = nil
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
    sessionFileErrors = manager.sessionFileErrors
  }

  private func persistSessionChanges() {
    do {
      try modelContextSaver(modelContext)
      lastPersistenceSaveError = nil
    } catch {
      lastPersistenceSaveError = error.localizedDescription
      modelContext?.rollback()
      performSync()
    }
  }

  private func beginTerminating(_ session: SessionRecord) {
    if selectedSessionId == session.sessionId {
      selectedSessionId = nil
    }
    session.beginClosing()
    sessionTerminationErrors[session.sessionId] = nil
    saveSessionChanges()
  }

  private func terminate(_ session: SessionRecord) async {
    do {
      try await sessionTerminator.close(sessionId: session.sessionId)
      session.close(byUser: true)
      sessionTerminationErrors[session.sessionId] = nil
      saveSessionChanges()
    } catch {
      session.markCloseFailed()
      sessionTerminationErrors[session.sessionId] = error.localizedDescription
      saveSessionChanges()
    }
  }

  private static func defaultScreenshotDirectory() -> URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }

  private static func defaultModelContextSaver(_ modelContext: ModelContext?) throws {
    try modelContext?.save()
  }
}

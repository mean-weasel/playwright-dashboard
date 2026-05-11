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
  var sessionTerminationErrors: [String: String] = [:]
  var sessionFileErrors: [String: String] = [:]
  var lastSavedScreenshotURL: URL?
  var lastScreenshotSaveError: String?
  var lastOpenURLError: String?
  var lastPersistenceSaveError: String?
  private var lastSessionSyncSaveError: String?
  private(set) var playwrightCLIStatus: PlaywrightCLIStatus = .unknown
  var isPersistenceDegraded = false
  var persistenceDegradedReason: String?
  var lastDiagnosticsExportURL: URL?
  var lastDiagnosticsExportError: String?
  private var browserControlAuthorizedSessionIds: Set<String> = []
  let sessionFileProvider: @MainActor () -> [URL]
  let daemonDirectory: URL
  private let startWatching: @MainActor () -> Void
  private let stopWatching: @MainActor () -> Void
  private let shouldStartScreenshots: Bool
  private let shouldStartPeriodicSync: Bool
  private let syncInterval: Duration
  private let sessionTerminator: SessionTerminator
  private let cliStatusProvider: PlaywrightCLIStatusProvider
  let safeModeProvider: @MainActor () -> Bool
  let screenshotDirectoryProvider: @MainActor () -> URL
  let urlOpener: @MainActor (URL) -> Bool
  private let sessionSyncModelContextSaver: @MainActor (ModelContext) throws -> Void
  private let modelContextSaver: @MainActor (ModelContext?) throws -> Void
  private var sessionManager: SessionManager?
  let screenshotService = ScreenshotService()
  private var syncTask: Task<Void, Never>?
  private var modelContext: ModelContext?

  init() {
    let watcher = DaemonWatcher()
    self.sessionFileProvider = { watcher.sessionFiles }
    self.daemonDirectory = DaemonWatcher.daemonDirectory
    self.startWatching = { watcher.start() }
    self.stopWatching = { watcher.stop() }
    self.shouldStartScreenshots = true
    self.shouldStartPeriodicSync = true
    self.syncInterval = .seconds(2)
    self.sessionTerminator = SessionTerminator()
    self.cliStatusProvider = PlaywrightCLIStatusProvider()
    self.safeModeProvider = { DashboardSettings.safeMode() }
    self.screenshotDirectoryProvider = Self.defaultScreenshotDirectory
    self.urlOpener = { NSWorkspace.shared.open($0) }
    self.sessionSyncModelContextSaver = { try $0.save() }
    self.modelContextSaver = Self.defaultModelContextSaver
  }
  init(daemonDirectory: URL, shouldStartScreenshots: Bool = true) {
    let watcher = DaemonWatcher(daemonDirectory: daemonDirectory)
    self.sessionFileProvider = { watcher.sessionFiles }
    self.daemonDirectory = daemonDirectory
    self.startWatching = { watcher.start() }
    self.stopWatching = { watcher.stop() }
    self.shouldStartScreenshots = shouldStartScreenshots
    self.shouldStartPeriodicSync = true
    self.syncInterval = .seconds(2)
    self.sessionTerminator = SessionTerminator()
    self.cliStatusProvider = PlaywrightCLIStatusProvider()
    self.safeModeProvider = { DashboardSettings.safeMode() }
    self.screenshotDirectoryProvider = Self.defaultScreenshotDirectory
    self.urlOpener = { NSWorkspace.shared.open($0) }
    self.sessionSyncModelContextSaver = { try $0.save() }
    self.modelContextSaver = Self.defaultModelContextSaver
  }
  init(
    sessionFileProvider: @escaping @MainActor () -> [URL],
    daemonDirectory: URL = DaemonWatcher.daemonDirectory,
    startWatching: @escaping @MainActor () -> Void = {},
    stopWatching: @escaping @MainActor () -> Void = {},
    shouldStartScreenshots: Bool = false,
    shouldStartPeriodicSync: Bool = false,
    syncInterval: Duration = .seconds(2),
    sessionTerminator: SessionTerminator = SessionTerminator(),
    cliStatusProvider: PlaywrightCLIStatusProvider = PlaywrightCLIStatusProvider(),
    safeModeProvider: @escaping @MainActor () -> Bool = { DashboardSettings.safeMode() },
    screenshotDirectoryProvider: @escaping @MainActor () -> URL =
      AppState.defaultScreenshotDirectory,
    urlOpener: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
    sessionSyncModelContextSaver: @escaping @MainActor (ModelContext) throws -> Void = {
      try $0.save()
    },
    modelContextSaver: @escaping @MainActor (ModelContext?) throws -> Void =
      AppState.defaultModelContextSaver
  ) {
    self.sessionFileProvider = sessionFileProvider
    self.daemonDirectory = daemonDirectory
    self.startWatching = startWatching
    self.stopWatching = stopWatching
    self.shouldStartScreenshots = shouldStartScreenshots
    self.shouldStartPeriodicSync = shouldStartPeriodicSync
    self.syncInterval = syncInterval
    self.sessionTerminator = sessionTerminator
    self.cliStatusProvider = cliStatusProvider
    self.safeModeProvider = safeModeProvider
    self.screenshotDirectoryProvider = screenshotDirectoryProvider
    self.urlOpener = urlOpener
    self.sessionSyncModelContextSaver = sessionSyncModelContextSaver
    self.modelContextSaver = modelContextSaver
  }

  /// Call once from a view that has access to the ModelContext.
  func startSync(modelContext: ModelContext) {
    guard sessionManager == nil else { return }

    let manager = SessionManager(
      sessionFileProvider: sessionFileProvider,
      modelContext: modelContext,
      modelContextSaver: sessionSyncModelContextSaver
    )
    self.sessionManager = manager
    self.modelContext = modelContext

    // Start watching the filesystem
    startWatching()
    if shouldStartScreenshots {
      screenshotService.start(appState: self)
    }

    // Kick off a periodic sync loop that reconciles watcher -> SwiftData -> sessions.
    if shouldStartPeriodicSync {
      Task { [weak self] in
        await self?.performSync()
      }
      syncTask = Task { [weak self] in
        while !Task.isCancelled {
          do {
            guard let self else { return }
            try await Task.sleep(for: self.syncInterval)
          } catch { break }
          guard let self else { return }
          await self.performSync()
        }
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

  func closeAndTerminate(_ session: SessionRecord) {
    guard !isSafeMode else { return }
    revokeBrowserControl(for: session)
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

  func refreshPlaywrightCLIStatus() {
    Task {
      playwrightCLIStatus = await cliStatusProvider.status()
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

  func authorizeBrowserControl(for session: SessionRecord) {
    browserControlAuthorizedSessionIds.insert(session.sessionId)
  }

  func revokeBrowserControl(for session: SessionRecord) {
    browserControlAuthorizedSessionIds.remove(session.sessionId)
  }

  func isBrowserControlAuthorized(for session: SessionRecord) -> Bool {
    browserControlAuthorizedSessionIds.contains(session.sessionId)
  }

  func saveSessionChanges() {
    persistSessionChanges()
  }

  func performSync() async {
    guard let manager = sessionManager else { return }
    await manager.syncWithWatcher()
    sessions = manager.allSessions
    sessionFileErrors = manager.sessionFileErrors
    let previousSyncSaveError = lastSessionSyncSaveError
    lastSessionSyncSaveError = manager.lastSaveError
    if let syncSaveError = manager.lastSaveError {
      lastPersistenceSaveError = syncSaveError
    } else if lastPersistenceSaveError == previousSyncSaveError {
      lastPersistenceSaveError = nil
    }
  }

  private func persistSessionChanges() {
    do {
      try modelContextSaver(modelContext)
      lastPersistenceSaveError = nil
    } catch {
      lastPersistenceSaveError = error.localizedDescription
      modelContext?.rollback()
      Task { [weak self] in
        await self?.performSync()
      }
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
}

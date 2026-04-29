import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppState {
  private(set) var sessions: [SessionRecord] = []
  var isPopoverOpen: Bool = false
  var isDashboardOpen: Bool = false
  var selectedSessionId: String?

  // Services
  private let sessionFileProvider: @MainActor () -> [URL]
  private let startWatching: @MainActor () -> Void
  private let stopWatching: @MainActor () -> Void
  private let shouldStartScreenshots: Bool
  private let syncInterval: Duration
  private var sessionManager: SessionManager?
  private let screenshotService = ScreenshotService()
  private var syncTask: Task<Void, Never>?

  init() {
    let watcher = DaemonWatcher()
    self.sessionFileProvider = { watcher.sessionFiles }
    self.startWatching = { watcher.start() }
    self.stopWatching = { watcher.stop() }
    self.shouldStartScreenshots = true
    self.syncInterval = .seconds(2)
  }

  init(
    sessionFileProvider: @escaping @MainActor () -> [URL],
    startWatching: @escaping @MainActor () -> Void = {},
    stopWatching: @escaping @MainActor () -> Void = {},
    shouldStartScreenshots: Bool = false,
    syncInterval: Duration = .seconds(2)
  ) {
    self.sessionFileProvider = sessionFileProvider
    self.startWatching = startWatching
    self.stopWatching = stopWatching
    self.shouldStartScreenshots = shouldStartScreenshots
    self.syncInterval = syncInterval
  }

  /// Call once from a view that has access to the ModelContext.
  func startSync(modelContext: ModelContext) {
    guard sessionManager == nil else { return }

    let manager = SessionManager(
      sessionFileProvider: sessionFileProvider, modelContext: modelContext)
    self.sessionManager = manager

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
    screenshotService.stop()
    stopWatching()
  }

  private func performSync() {
    guard let manager = sessionManager else { return }
    manager.syncWithWatcher()
    sessions = manager.allSessions
  }
}

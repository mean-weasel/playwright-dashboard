import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppState {
    private(set) var sessions: [SessionRecord] = []
    var isPopoverOpen: Bool = false
    var isDashboardOpen: Bool = false
    var selectedSessionId: String?

    // Services
    private let daemonWatcher = DaemonWatcher()
    private var sessionManager: SessionManager?
    private let screenshotService = ScreenshotService()
    private var syncTask: Task<Void, Never>?

    /// Call once from a view that has access to the ModelContext.
    func startSync(modelContext: ModelContext) {
        guard sessionManager == nil else { return }

        let manager = SessionManager(watcher: daemonWatcher, modelContext: modelContext)
        self.sessionManager = manager

        // Start watching the filesystem
        daemonWatcher.start()

        // Kick off a periodic sync loop that reconciles watcher → SwiftData → sessions
        syncTask = Task { [weak self] in
            // Brief delay for FSEvents to deliver initial batch
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch { return }

            guard let self else { return }
            self.performSync()
            self.screenshotService.start(appState: self)

            // Poll every 2 seconds to pick up changes
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch { break }
                self.performSync()
            }
        }
    }

    /// Cancel the sync loop and stop all services.
    func stopSync() {
        syncTask?.cancel()
        syncTask = nil
        screenshotService.stop()
        daemonWatcher.stop()
    }

    private func performSync() {
        guard let manager = sessionManager else { return }
        manager.syncWithWatcher()
        sessions = manager.activeSessions
    }
}

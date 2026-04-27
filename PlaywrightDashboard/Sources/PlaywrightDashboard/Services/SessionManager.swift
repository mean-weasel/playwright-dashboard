import Foundation
import Observation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "SessionManager")

/// Bridges `DaemonWatcher` (file events) and `SessionRecord` (SwiftData).
///
/// When the watcher's `sessionFiles` list changes, SessionManager:
///  - Parses each `.session` file into a `SessionFileConfig`
///  - Creates new `SessionRecord` entries for sessions not yet in the store
///  - Updates existing entries when the file content changes
///  - Marks sessions as `.closed` when their file disappears
@Observable
@MainActor
final class SessionManager {

    // MARK: - Public state

    /// All non-closed sessions, sorted by gridOrder then createdAt.
    var activeSessions: [SessionRecord] {
        allRecords
            .filter { $0.status != .closed }
            .sorted {
                if $0.gridOrder != $1.gridOrder { return $0.gridOrder < $1.gridOrder }
                return $0.createdAt < $1.createdAt
            }
    }

    // MARK: - Private state

    /// Snapshot of all SessionRecord objects managed here (avoids repeated fetches).
    private var allRecords: [SessionRecord] = []

    private let watcher: DaemonWatcher
    private let modelContext: ModelContext

    // MARK: - Init

    init(watcher: DaemonWatcher, modelContext: ModelContext) {
        self.watcher = watcher
        self.modelContext = modelContext
        loadExistingRecords()
    }

    // MARK: - Sync

    /// Called whenever `DaemonWatcher.sessionFiles` changes.
    /// Reconciles the on-disk list with the SwiftData store.
    func syncWithWatcher() {
        let fileURLs = watcher.sessionFiles

        // Parse all files and collect the canonical session IDs from JSON
        var liveConfigs: [SessionFileConfig] = []
        for url in fileURLs {
            guard let config = parseSessionFile(at: url) else { continue }
            liveConfigs.append(config)
        }

        let liveIds = Set(liveConfigs.map(\.name))

        // 1. Upsert each live config
        for config in liveConfigs {
            upsert(config: config)
        }

        // 2. Mark disappeared sessions as closed
        for record in allRecords where !record.sessionId.isEmpty {
            if record.status != .closed && !liveIds.contains(record.sessionId) {
                record.status = .closed
                record.closedAt = Date()
            }
        }

        // 3. Persist
        do {
            try modelContext.save()
        } catch {
            logger.error("SwiftData save failed: \(error.localizedDescription)")
            modelContext.rollback()
            loadExistingRecords()
        }
    }

    // MARK: - Private helpers

    /// Load all existing SessionRecord objects from SwiftData into our local cache.
    private func loadExistingRecords() {
        let descriptor = FetchDescriptor<SessionRecord>()
        do {
            allRecords = try modelContext.fetch(descriptor)
        } catch {
            logger.error("SwiftData fetch failed: \(error.localizedDescription)")
            allRecords = []
        }
    }

    /// Parse a `.session` file URL into a `SessionFileConfig`.
    private func parseSessionFile(at url: URL) -> SessionFileConfig? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.debug("Cannot read session file \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        do {
            return try JSONDecoder().decode(SessionFileConfig.self, from: data)
        } catch {
            logger.warning("Cannot parse session file \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Insert a new SessionRecord or update an existing one.
    private func upsert(config: SessionFileConfig) {
        let port = config.cdpPort ?? 0

        if let existing = allRecords.first(where: { $0.sessionId == config.name }) {
            // Update mutable fields that can change between file writes
            if existing.socketPath != config.socketPath {
                existing.socketPath = config.socketPath
            }
            if existing.workspaceDir != config.workspaceDir {
                existing.workspaceDir = config.workspaceDir
                existing.workspaceName = URL(fileURLWithPath: config.workspaceDir).lastPathComponent
                existing.projectName = SessionRecord.extractProjectName(from: config.workspaceDir)
            }
            if existing.cdpPort != port {
                existing.cdpPort = port
            }
            // Reopen a previously closed session that has re-appeared on disk
            if existing.status == .closed {
                existing.status = .idle
                existing.closedAt = nil
                existing.lastActivityAt = Date()
            }
            // Refresh auto-label in case workspace changed
            AutoLabeler.label(for: existing)
        } else {
            // New session — assign the next available gridOrder
            let nextOrder = (allRecords.map(\.gridOrder).max() ?? -1) + 1
            let record = SessionRecord(
                sessionId: config.name,
                autoLabel: config.name,
                workspaceDir: config.workspaceDir,
                cdpPort: port,
                socketPath: config.socketPath,
                gridOrder: nextOrder,
                status: .idle
            )
            AutoLabeler.label(for: record)
            modelContext.insert(record)
            allRecords.append(record)
        }
    }
}

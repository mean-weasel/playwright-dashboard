import Foundation
import Observation
import SwiftData

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
        let liveIds = Set(fileURLs.compactMap { sessionId(from: $0) })

        // 1. Parse & upsert each live file
        for url in fileURLs {
            guard let config = parseSessionFile(at: url) else { continue }
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
        try? modelContext.save()
    }

    // MARK: - Private helpers

    /// Load all existing SessionRecord objects from SwiftData into our local cache.
    private func loadExistingRecords() {
        let descriptor = FetchDescriptor<SessionRecord>()
        allRecords = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Extracts the session id (the `name` field) from a `.session` file URL.
    /// The filename format is `<uuid>-<name>.session`, but the canonical id is
    /// stored inside the JSON as `name`.  We parse the file anyway; this is
    /// just a quick fallback for set lookups.
    private func sessionId(from url: URL) -> String? {
        // Try to derive the id from the filename stem: `<hash>-<name>.session`
        // Actual id comes from the JSON `name` field when we parse.
        // Return the stem (everything before the last `-` separated token).
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }

    /// Parse a `.session` file URL into a `SessionFileConfig`.
    private func parseSessionFile(at url: URL) -> SessionFileConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionFileConfig.self, from: data)
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
        } else {
            // New session — assign the next available gridOrder
            let nextOrder = (allRecords.map(\.gridOrder).max() ?? -1) + 1
            let record = SessionRecord(
                sessionId: config.name,
                autoLabel: config.name,   // Task 7 will compute a smarter label
                workspaceDir: config.workspaceDir,
                cdpPort: port,
                socketPath: config.socketPath,
                gridOrder: nextOrder,
                status: .idle
            )
            modelContext.insert(record)
            allRecords.append(record)
        }
    }
}

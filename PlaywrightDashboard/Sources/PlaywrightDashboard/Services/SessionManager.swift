import Foundation
import OSLog
import Observation
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

  /// All sessions sorted by gridOrder then createdAt.
  var allSessions: [SessionRecord] {
    allRecords
      .sorted {
        if $0.gridOrder != $1.gridOrder { return $0.gridOrder < $1.gridOrder }
        return $0.createdAt < $1.createdAt
      }
  }
  private(set) var sessionFileErrors: [String: String] = [:]

  // MARK: - Private state

  /// Snapshot of all SessionRecord objects managed here (avoids repeated fetches).
  private var allRecords: [SessionRecord] = []

  private let sessionFileProvider: @MainActor () -> [URL]
  private let modelContext: ModelContext
  private let closedSessionRetentionProvider: () -> Duration?
  private let sessionFileScanner: SessionFileScanner
  private let modelContextSaver: @MainActor (ModelContext) throws -> Void
  private(set) var lastSaveError: String?

  // MARK: - Init

  init(watcher: DaemonWatcher, modelContext: ModelContext) {
    self.sessionFileProvider = { watcher.sessionFiles }
    self.modelContext = modelContext
    self.closedSessionRetentionProvider = { DashboardSettings.closedSessionRetention() }
    self.sessionFileScanner = SessionFileScanner()
    self.modelContextSaver = { try $0.save() }
    loadExistingRecords()
  }

  init(
    sessionFileProvider: @escaping @MainActor () -> [URL],
    modelContext: ModelContext,
    closedSessionRetentionProvider: @escaping () -> Duration? = {
      DashboardSettings.closedSessionRetention()
    },
    sessionFileScanner: SessionFileScanner = SessionFileScanner(),
    modelContextSaver: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
  ) {
    self.sessionFileProvider = sessionFileProvider
    self.modelContext = modelContext
    self.closedSessionRetentionProvider = closedSessionRetentionProvider
    self.sessionFileScanner = sessionFileScanner
    self.modelContextSaver = modelContextSaver
    loadExistingRecords()
  }

  // MARK: - Sync

  /// Called whenever `DaemonWatcher.sessionFiles` changes.
  /// Reconciles the on-disk list with the SwiftData store.
  func syncWithWatcher() async {
    let fileURLs = sessionFileProvider()
    let scanResult = await sessionFileScanner.scan(fileURLs)
    sessionFileErrors = scanResult.errors

    let liveConfigs = scanResult.configs
    let liveIds = Set(liveConfigs.map(\.name))
    let presentButUnresolvedIds = scanResult.unresolvedSessionIds

    // 1. Upsert each live config
    for config in liveConfigs {
      upsert(config: config)
    }

    // 2. Mark disappeared sessions as closed (auto-close, not user-initiated)
    for record in allRecords where !record.sessionId.isEmpty {
      if record.status != .closed && record.status != .closing
        && !liveIds.contains(record.sessionId)
        && !presentButUnresolvedIds.contains(record.sessionId)
      {
        record.close(byUser: false)
      }
    }

    purgeExpiredClosedRecords(liveIds: liveIds)

    // 3. Persist
    do {
      try modelContextSaver(modelContext)
      lastSaveError = nil
    } catch {
      lastSaveError = error.localizedDescription
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
      // Reopen a previously closed session that has re-appeared on disk,
      // but only if it was auto-closed (not user-initiated).
      if existing.status == .closed && !existing.userClosed {
        existing.reopen()
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

  private func purgeExpiredClosedRecords(liveIds: Set<String>) {
    guard let retention = closedSessionRetentionProvider() else { return }
    let cutoff = Date().addingTimeInterval(-retention.timeInterval)
    var keptRecords: [SessionRecord] = []

    for record in allRecords {
      let shouldPurge =
        record.status == .closed
        && !liveIds.contains(record.sessionId)
        && (record.closedAt ?? record.createdAt) < cutoff

      if shouldPurge {
        modelContext.delete(record)
      } else {
        keptRecords.append(record)
      }
    }

    allRecords = keptRecords
  }
}

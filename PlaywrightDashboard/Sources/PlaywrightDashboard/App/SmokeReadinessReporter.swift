import Foundation

@MainActor
enum SmokeReadinessReporter {
  private static var directory: URL?
  private static var navigationURL: String?
  private static var consumedNavigationSessionIds: Set<String> = []

  static var isEnabled: Bool {
    directory != nil
  }

  static func configure(directory: URL?, navigationURL: String?) {
    self.directory = directory
    self.navigationURL = navigationURL
    consumedNavigationSessionIds.removeAll()
  }

  static func navigationURLForExpandedSession(_ sessionId: String) -> String? {
    guard let navigationURL, !consumedNavigationSessionIds.contains(sessionId) else {
      return nil
    }
    consumedNavigationSessionIds.insert(sessionId)
    return navigationURL
  }

  static func writeDashboard(
    appState: AppState,
    safeMode: Bool,
    activeFilter: SidebarFilter?,
    searchQuery: String
  ) {
    guard let directory else { return }
    let payload = DashboardPayload(
      selectedSessionId: appState.selectedSessionId,
      safeMode: safeMode,
      activeFilter: activeFilter.map(\.smokeIdentifier) ?? "none",
      searchQuery: searchQuery,
      sessions: appState.sessions.map(SessionPayload.init(session:))
    )
    write(payload, named: "dashboard-ready.json", to: directory)
  }

  static func writeExpanded(
    session: SessionRecord,
    safeMode: Bool,
    interactionEnabled: Bool,
    frameMode: ExpandedFrameMode,
    targetMonitorMode: ExpandedTargetMonitorMode,
    navigationResult: String? = nil,
    navigationError: String? = nil
  ) {
    guard let directory else { return }
    let payload = ExpandedPayload(
      session: SessionPayload(session: session),
      safeMode: safeMode,
      interactionEnabled: interactionEnabled,
      navigationEnabled: !safeMode && session.cdpPort > 0,
      cdpInspectorEnabled: !safeMode && session.cdpPort > 0,
      frameMode: String(describing: frameMode),
      targetMonitorMode: String(describing: targetMonitorMode),
      navigationResult: navigationResult,
      navigationError: navigationError
    )
    write(payload, named: "expanded-ready.json", to: directory)
  }

  private static func write<T: Encodable>(_ payload: T, named filename: String, to directory: URL) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      let temporaryURL = directory.appendingPathComponent(".\(filename).tmp")
      let finalURL = directory.appendingPathComponent(filename)
      try data.write(to: temporaryURL, options: .atomic)
      try? FileManager.default.removeItem(at: finalURL)
      try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
    } catch {
      fputs("Smoke readiness write failed: \(error)\n", stderr)
    }
  }
}

private struct DashboardPayload: Encodable {
  let selectedSessionId: String?
  let safeMode: Bool
  let activeFilter: String
  let searchQuery: String
  let sessions: [SessionPayload]
}

private struct ExpandedPayload: Encodable {
  let session: SessionPayload
  let safeMode: Bool
  let interactionEnabled: Bool
  let navigationEnabled: Bool
  let cdpInspectorEnabled: Bool
  let frameMode: String
  let targetMonitorMode: String
  let navigationResult: String?
  let navigationError: String?
}

extension SidebarFilter {
  var smokeIdentifier: String {
    switch self {
    case .allOpen: "allOpen"
    case .idleStale: "idleStale"
    case .closed: "closed"
    case .workspace(let name): "workspace:\(name)"
    }
  }
}

private struct SessionPayload: Encodable {
  let sessionId: String
  let displayName: String
  let status: String
  let cdpPort: Int
  let lastURL: String?
  let lastTitle: String?
  let pageTargetCount: Int
  let selectedTargetId: String?

  init(session: SessionRecord) {
    self.sessionId = session.sessionId
    self.displayName = session.displayName
    self.status = session.status.rawValue
    self.cdpPort = session.cdpPort
    self.lastURL = session.lastURL
    self.lastTitle = session.lastTitle
    self.pageTargetCount = session.pageTargets.count
    self.selectedTargetId = session.selectedTargetId
  }
}

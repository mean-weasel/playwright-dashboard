import Foundation

@MainActor
enum SmokeStartupActions {
  private static let pollInterval: TimeInterval = 0.25
  private static let deadlineInterval: TimeInterval = 30

  static func start(arguments: SmokeLaunchArguments, appState: AppState) {
    var pending: [Action] = []
    if let sessionId = arguments.renameSessionId, let name = arguments.renameTo {
      pending.append(.rename(sessionId: sessionId, to: name))
    }
    if let sessionId = arguments.markSessionClosedId {
      pending.append(.markClosed(sessionId: sessionId))
    }
    if let sourceId = arguments.reorderSourceId, let targetId = arguments.reorderTargetId {
      pending.append(.reorder(sourceId: sourceId, targetId: targetId))
    }
    if let sessionId = arguments.closeSessionId {
      pending.append(.closeViaDashboard(sessionId: sessionId))
    }
    if let sessionId = arguments.markSessionStaleId, arguments.cleanupStaleSessions {
      pending.append(.markAndCleanupStale(sessionId: sessionId))
    }
    guard !pending.isEmpty else { return }

    let deadline = Date().addingTimeInterval(deadlineInterval)
    schedulePoll(appState: appState, pending: pending, deadline: deadline)
  }

  private static func schedulePoll(
    appState: AppState,
    pending: [Action],
    deadline: Date
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
      Task { @MainActor in
        let remaining = applyReady(actions: pending, appState: appState)
        if remaining.isEmpty { return }
        if Date() > deadline {
          let names = remaining.map(\.description).joined(separator: ", ")
          fputs("SmokeStartupActions timed out waiting for: \(names)\n", stderr)
          return
        }
        schedulePoll(appState: appState, pending: remaining, deadline: deadline)
      }
    }
  }

  private static func applyReady(actions: [Action], appState: AppState) -> [Action] {
    var unfinished: [Action] = []
    for action in actions {
      switch action {
      case .rename(let sessionId, let name):
        if let session = appState.sessions.first(where: { $0.sessionId == sessionId }) {
          appState.rename(session, to: name)
        } else {
          unfinished.append(action)
        }
      case .markClosed(let sessionId):
        if let session = appState.sessions.first(where: { $0.sessionId == sessionId }) {
          session.close(byUser: true)
          appState.saveSessionChanges()
          if appState.selectedSessionId == sessionId {
            appState.selectedSessionId = nil
          }
        } else {
          unfinished.append(action)
        }
      case .reorder(let sourceId, let targetId):
        let hasSource = appState.sessions.contains(where: { $0.sessionId == sourceId })
        let hasTarget = appState.sessions.contains(where: { $0.sessionId == targetId })
        if hasSource && hasTarget {
          _ = appState.reorder(sourceId: sourceId, targetId: targetId)
        } else {
          unfinished.append(action)
        }
      case .closeViaDashboard(let sessionId):
        if let session = appState.sessions.first(where: { $0.sessionId == sessionId }) {
          appState.closeAndTerminate(session)
        } else {
          unfinished.append(action)
        }
      case .markAndCleanupStale(let sessionId):
        if let session = appState.sessions.first(where: { $0.sessionId == sessionId }) {
          session.status = .stale
          appState.saveSessionChanges()
          appState.closeAndTerminateStaleSessions()
        } else {
          unfinished.append(action)
        }
      }
    }
    return unfinished
  }

  private enum Action: CustomStringConvertible {
    case rename(sessionId: String, to: String)
    case markClosed(sessionId: String)
    case reorder(sourceId: String, targetId: String)
    case closeViaDashboard(sessionId: String)
    case markAndCleanupStale(sessionId: String)

    var description: String {
      switch self {
      case .rename(let id, let name): "rename(\(id) -> \(name))"
      case .markClosed(let id): "markClosed(\(id))"
      case .reorder(let source, let target): "reorder(\(source) <-> \(target))"
      case .closeViaDashboard(let id): "closeViaDashboard(\(id))"
      case .markAndCleanupStale(let id): "markAndCleanupStale(\(id))"
      }
    }
  }
}

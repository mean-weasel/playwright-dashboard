import Foundation

@MainActor
extension AppState {
  func rename(_ session: SessionRecord, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    session.customName = trimmed.isEmpty ? nil : trimmed
    saveSessionChanges()
  }

  func close(_ session: SessionRecord, byUser: Bool = true) {
    guard !isSafeMode else { return }
    revokeBrowserControl(for: session)
    if selectedSessionId == session.sessionId {
      selectedSessionId = nil
    }
    session.close(byUser: byUser)
    saveSessionChanges()
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
      revokeBrowserControl(for: session)
      session.close(byUser: true)
    }
    if didCloseSelectedSession {
      selectedSessionId = nil
    }
    saveSessionChanges()
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

  @discardableResult
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
}

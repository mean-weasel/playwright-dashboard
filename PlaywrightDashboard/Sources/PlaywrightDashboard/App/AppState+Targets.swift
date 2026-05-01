import Foundation

@MainActor
extension AppState {
  func selectTarget(_ session: SessionRecord, targetId: String?) {
    session.selectPageTarget(id: targetId)
    saveSessionChanges()
  }

  @discardableResult
  func refreshTargets(_ session: SessionRecord, pages: [CDPClient.PageInfo]) -> Bool {
    refreshTargets(session, targets: CDPPageTargetSelection.selectableTargets(from: pages))
  }

  @discardableResult
  func refreshTargets(_ session: SessionRecord, targets: [CDPPageTarget]) -> Bool {
    guard session.status != .closed else { return false }

    let didChange = session.updatePageTargets(targets)
    if didChange {
      saveSessionChanges()
    }
    return didChange
  }
}

extension ExpandedSessionView {
  func backAction() {
    if let onBack {
      onBack()
    } else {
      appState.selectedSessionId = nil
    }
  }

  var detachedWindowAction: (() -> Void)? {
    guard onBack == nil else { return nil }
    return {
      openWindow(value: session.sessionId)
    }
  }
}

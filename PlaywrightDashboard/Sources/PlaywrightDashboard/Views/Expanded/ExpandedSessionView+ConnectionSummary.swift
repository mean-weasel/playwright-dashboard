extension ExpandedSessionView {
  var connectionSummary: ExpandedConnectionSummary {
    ExpandedConnectionSummary(
      frameMode: frameMode,
      targetMode: targetMonitorMode,
      targetCount: session.pageTargets.count,
      selectedTarget: session.selectedPageTarget,
      lastCDPError: lastCDPError,
      lastTargetError: lastTargetRefreshError
    )
  }
}

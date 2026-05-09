import Foundation

extension ExpandedSessionView {
  var smokeCommandSignature: String {
    "\(session.sessionId):\(safeMode):\(interactionEnabled)"
  }

  var expandedReadinessSignature: String {
    [
      session.sessionId,
      session.lastURL ?? "",
      String(safeMode),
      String(effectiveInteractionEnabled),
      String(describing: frameMode),
      String(describing: targetMonitorMode),
      smokeNavigationResult ?? "",
      smokeNavigationError ?? "",
    ].joined(separator: "|")
  }

  func reportSmokeExpandedReadiness() {
    SmokeReadinessReporter.writeExpanded(
      session: session,
      safeMode: safeMode,
      interactionEnabled: effectiveInteractionEnabled,
      frameMode: frameMode,
      targetMonitorMode: targetMonitorMode,
      navigationResult: smokeNavigationResult,
      navigationError: smokeNavigationError
    )
  }

  func runSmokeNavigationIfNeeded() async {
    guard let url = SmokeReadinessReporter.navigationURLForExpandedSession(session.sessionId) else {
      return
    }
    do {
      let result = try await navigate(to: url)
      smokeNavigationResult = result
      smokeNavigationError = nil
    } catch {
      smokeNavigationResult = nil
      smokeNavigationError = error.localizedDescription
    }
    reportSmokeExpandedReadiness()
  }
}

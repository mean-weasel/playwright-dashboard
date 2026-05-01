import OSLog
import SwiftUI

private let targetLogger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedTargets")

extension ExpandedSessionView {
  /// Refreshes CDP page targets independently of screenshot or screencast frames.
  func targetRefreshLoop() async {
    guard session.cdpPort > 0 else { return }
    targetMonitorMode = .connecting
    lastTargetRefreshError = nil
    let monitor = CDPTargetMonitor(port: session.cdpPort)

    do {
      for try await targets in await monitor.targetUpdates() {
        guard !Task.isCancelled, session.status != .closed else { break }
        targetMonitorMode = .eventStream
        lastTargetRefreshError = nil
        appState.refreshTargets(session, targets: targets)
      }
    } catch is CancellationError {
      return
    } catch {
      targetMonitorMode = .polling
      lastTargetRefreshError = error.localizedDescription
      targetLogger.debug(
        "Target event stream failed on port \(session.cdpPort): \(error.localizedDescription)")
    }

    await targetPollingLoop()
  }

  private func targetPollingLoop() async {
    let client = CDPClient(port: session.cdpPort)

    while !Task.isCancelled {
      guard session.status != .closed else { break }

      do {
        let pages = try await client.listPages()
        targetMonitorMode = .polling
        lastTargetRefreshError = nil
        appState.refreshTargets(session, pages: pages)
      } catch is CancellationError {
        break
      } catch {
        targetMonitorMode = .unavailable
        lastTargetRefreshError = error.localizedDescription
        targetLogger.debug(
          "Target refresh failed on port \(session.cdpPort): \(error.localizedDescription)")
      }

      do {
        try await Task.sleep(for: .seconds(3))
      } catch { break }
    }
  }
}

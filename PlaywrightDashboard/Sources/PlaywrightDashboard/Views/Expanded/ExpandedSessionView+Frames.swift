import OSLog
import SwiftUI

private let frameLogger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedFrames")

extension ExpandedSessionView {
  func streamOrFallbackLoop() async {
    guard session.cdpPort > 0 else { return }
    let connection = CDPPageConnection(port: session.cdpPort, targetId: session.selectedTargetId)
    pageConnection = connection
    fallbackInputClient = nil
    isScreencasting = false
    isSnapshotFallback = false
    frameMode = .waiting
    lastCDPError = nil
    frameCountSinceSave = 0

    if DashboardSettings.forceExpandedSnapshotFallback() {
      isSnapshotFallback = true
      frameMode = .snapshotFallback
      await fastRefreshLoop(client: CDPClient(port: session.cdpPort))
      return
    }

    do {
      let frames = try await connection.startScreencast(
        quality: DashboardSettings.expandedQuality())
      for try await frame in frames {
        guard !Task.isCancelled, session.status != .closed else { break }
        applyScreencastFrame(frame)
      }
      await connection.close()
      pageConnection = nil
    } catch is CancellationError {
      await connection.close()
      pageConnection = nil
    } catch {
      await connection.close()
      pageConnection = nil
      isScreencasting = false
      isSnapshotFallback = true
      frameMode = .snapshotFallback
      consecutiveFailures += 1
      lastCDPError = error.localizedDescription
      frameLogger.warning(
        "Screencast failed on port \(session.cdpPort): \(error.localizedDescription). Falling back to screenshot polling."
      )
      await fastRefreshLoop(client: CDPClient(port: session.cdpPort))
    }
  }

  private func applyScreencastFrame(_ frame: CDPClient.ScreencastFrame) {
    let result = CDPClient.ScreenshotResult(
      jpeg: frame.jpeg,
      url: frame.url,
      title: frame.title
    )
    session.updateFromScreenshot(result)
    isScreencasting = true
    isSnapshotFallback = false
    frameMode = .liveScreencast
    lastCDPError = nil
    consecutiveFailures = 0
    frameCountSinceSave += 1

    // Persist occasional frames so Save Screenshot and history stay recent
    // without writing SwiftData on every screencast frame.
    if frameCountSinceSave >= 30 {
      frameCountSinceSave = 0
      appState.saveSessionChanges()
    }
  }

  private func fastRefreshLoop(client: CDPClient) async {
    guard session.cdpPort > 0 else { return }
    fallbackInputClient = client

    while !Task.isCancelled {
      guard session.status != .closed else { break }

      do {
        let result = try await client.captureScreenshot(
          quality: DashboardSettings.expandedQuality(),
          targetId: session.selectedTargetId)
        guard session.status != .closed else { break }
        session.updateFromScreenshot(result)
        appState.saveSessionChanges()
        frameMode = .snapshotFallback
        lastCDPError = nil
        consecutiveFailures = 0
      } catch is CancellationError {
        break
      } catch {
        consecutiveFailures += 1
        frameMode = consecutiveFailures >= failureWarningThreshold ? .connectionLost : frameMode
        lastCDPError = error.localizedDescription
        frameLogger.warning(
          "Fast refresh failed on port \(session.cdpPort) (\(consecutiveFailures)x): \(error.localizedDescription)"
        )
      }

      do {
        try await Task.sleep(for: DashboardSettings.expandedRefreshDuration())
      } catch { break }
    }
  }
}

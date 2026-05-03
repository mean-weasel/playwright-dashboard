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
    currentFrameImage = nil
    currentFrameResult = nil
    framesSinceLastPersist = 0
    hasPersistedScreencastFrame = false
    showsAgentActivityWarning = false
    agentActivityDismissTask?.cancel()
    agentActivityDismissTask = nil

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
      persistLatestScreencastFrameIfNeeded()
      if isRecording {
        stopRecording()
      }
      await connection.close()
      pageConnection = nil
    } catch is CancellationError {
      persistLatestScreencastFrameIfNeeded()
      if isRecording {
        stopRecording()
      }
      await connection.close()
      pageConnection = nil
    } catch {
      persistLatestScreencastFrameIfNeeded()
      if isRecording {
        stopRecording()
      }
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
    let previousResult = currentFrameResult
    detectAgentActivityIfNeeded(previous: previousResult, new: result)
    currentFrameResult = result
    if let image = NSImage(data: frame.jpeg) {
      currentFrameImage = image
    }
    isScreencasting = true
    isSnapshotFallback = false
    frameMode = .liveScreencast
    lastCDPError = nil
    consecutiveFailures = 0
    framesSinceLastPersist += 1
    appendRecordingFrame(frame)

    // Persist occasional frames so Save Screenshot and history stay recent
    // without routing live rendering through SwiftData on every frame.
    if ExpandedFramePersistencePolicy.shouldPersist(
      hasPersistedFrame: hasPersistedScreencastFrame,
      framesSinceLastPersist: framesSinceLastPersist
    ) {
      persistScreencastFrame(result)
    }
  }

  private func persistLatestScreencastFrameIfNeeded() {
    guard framesSinceLastPersist > 0, let currentFrameResult else { return }
    persistScreencastFrame(currentFrameResult)
  }

  private func persistScreencastFrame(_ result: CDPClient.ScreenshotResult) {
    session.updateFromScreenshot(result)
    appState.saveSessionChanges()
    framesSinceLastPersist = 0
    hasPersistedScreencastFrame = true
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
        let previousResult = currentFrameResult
        detectAgentActivityIfNeeded(previous: previousResult, new: result)
        currentFrameResult = result
        if let image = NSImage(data: result.jpeg) {
          currentFrameImage = image
        }
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

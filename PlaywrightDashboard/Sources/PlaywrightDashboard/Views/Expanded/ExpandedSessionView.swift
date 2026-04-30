import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  @AppStorage("expandedShowMetadata") private var showMetadata = true
  @AppStorage("expandedInteractionEnabled") private var interactionEnabled = false
  @State private var consecutiveFailures = 0
  @State private var pageConnection: CDPPageConnection?
  @State private var fallbackInputClient: CDPClient?
  @State private var isScreencasting = false
  @State private var isSnapshotFallback = false
  @State private var frameCountSinceSave = 0

  /// Show a warning after this many consecutive CDP failures.
  private let failureWarningThreshold = 5

  var body: some View {
    VStack(spacing: 0) {
      SessionInfoBar(
        session: session,
        onBack: { appState.selectedSessionId = nil },
        showMetadata: $showMetadata,
        interactionEnabled: $interactionEnabled
      )

      Divider()

      HStack(spacing: 0) {
        screenshotArea
        if showMetadata {
          Divider()
          SessionMetadataPanel(session: session)
            .transition(.move(edge: .trailing))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: showMetadata)
    }
    .task(id: session.sessionId) {
      await streamOrFallbackLoop()
    }
  }

  // MARK: - Screenshot Area

  private var screenshotArea: some View {
    Group {
      if session.cdpPort <= 0 {
        VStack(spacing: 12) {
          Image(systemName: "antenna.radiowaves.left.and.right.slash")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("No CDP port available")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("This session doesn't have browser debugging enabled.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      } else if let nsImage = session.screenshotImage {
        ZStack(alignment: .topTrailing) {
          InteractiveScreenshotSurface(
            image: nsImage,
            interactionEnabled: interactionEnabled,
            onClick: dispatchClick,
            onScroll: dispatchScroll,
            onKeyPress: dispatchKeyPress
          )
          .padding(20)

          ExpandedRefreshBadge(
            isScreencasting: isScreencasting,
            isSnapshotFallback: isSnapshotFallback
          )
          .padding(28)

          if interactionEnabled {
            ExpandedInteractionBadge()
              .padding(.top, 58)
              .padding(.trailing, 28)
          }

          if consecutiveFailures >= failureWarningThreshold {
            ExpandedConnectionWarningBadge()
              .padding(.top, interactionEnabled ? 88 : 58)
              .padding(.trailing, 28)
          }
        }
      } else if consecutiveFailures >= failureWarningThreshold {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.orange)
          Text("Unable to connect to browser")
            .font(.subheadline)
          Text("CDP port \(session.cdpPort) is not responding.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(spacing: 12) {
          ProgressView()
            .controlSize(.large)
          Text("Loading browser snapshot...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func dispatchClick(_ point: CGPoint) {
    guard interactionEnabled, session.cdpPort > 0 else { return }
    Task {
      do {
        if let pageConnection {
          try await pageConnection.dispatchMouseClick(x: point.x, y: point.y)
        } else {
          try await currentFallbackInputClient().dispatchMouseClick(x: point.x, y: point.y)
        }
      } catch {
        logger.warning("Mouse click dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  private func dispatchScroll(_ point: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
    guard interactionEnabled, session.cdpPort > 0 else { return }
    Task {
      do {
        if let pageConnection {
          try await pageConnection.dispatchMouseWheel(
            x: point.x,
            y: point.y,
            deltaX: Double(deltaX),
            deltaY: Double(-deltaY)
          )
        } else {
          try await currentFallbackInputClient().dispatchMouseWheel(
            x: point.x,
            y: point.y,
            deltaX: Double(deltaX),
            deltaY: Double(-deltaY)
          )
        }
      } catch {
        logger.warning("Mouse wheel dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  private func dispatchKeyPress(_ input: CDPClient.KeyEventInput) {
    guard interactionEnabled, session.cdpPort > 0 else { return }
    Task {
      do {
        if let pageConnection {
          try await pageConnection.dispatchKeyPress(input)
        } else {
          try await currentFallbackInputClient().dispatchKeyPress(input)
        }
      } catch {
        logger.warning("Key dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  private func currentFallbackInputClient() -> CDPClient {
    if let fallbackInputClient { return fallbackInputClient }
    let client = CDPClient(port: session.cdpPort)
    fallbackInputClient = client
    return client
  }

  // MARK: - Refresh

  private func streamOrFallbackLoop() async {
    guard session.cdpPort > 0 else { return }
    let connection = CDPPageConnection(port: session.cdpPort)
    pageConnection = connection
    fallbackInputClient = nil
    isScreencasting = false
    isSnapshotFallback = false
    frameCountSinceSave = 0

    if DashboardSettings.forceExpandedSnapshotFallback() {
      isSnapshotFallback = true
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
      return
    } catch {
      await connection.close()
      pageConnection = nil
      isScreencasting = false
      isSnapshotFallback = true
      consecutiveFailures += 1
      logger.warning(
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
    consecutiveFailures = 0
    frameCountSinceSave += 1

    // Persist occasional frames so Save Screenshot and session history have recent data
    // without writing SwiftData on every screencast frame.
    if frameCountSinceSave >= 30 {
      frameCountSinceSave = 0
      appState.saveSessionChanges()
    }
  }

  /// Polls CDP for screenshots when Page.startScreencast is unavailable.
  private func fastRefreshLoop() async {
    await fastRefreshLoop(client: CDPClient(port: session.cdpPort))
  }

  private func fastRefreshLoop(client: CDPClient) async {
    guard session.cdpPort > 0 else { return }
    fallbackInputClient = client

    while !Task.isCancelled {
      guard session.status != .closed else { break }

      do {
        let result = try await client.captureScreenshot(
          quality: DashboardSettings.expandedQuality())
        guard session.status != .closed else { break }
        session.updateFromScreenshot(result)
        appState.saveSessionChanges()
        consecutiveFailures = 0
      } catch is CancellationError {
        break
      } catch {
        consecutiveFailures += 1
        logger.warning(
          "Fast refresh failed on port \(session.cdpPort) (\(consecutiveFailures)x): \(error.localizedDescription)"
        )
      }

      do {
        try await Task.sleep(for: DashboardSettings.expandedRefreshDuration())
      } catch { break }
    }
  }
}

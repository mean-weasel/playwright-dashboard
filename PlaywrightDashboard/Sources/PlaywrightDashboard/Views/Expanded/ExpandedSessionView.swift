import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) var appState
  @Environment(\.openWindow) var openWindow
  let session: SessionRecord
  var onBack: (() -> Void)?
  @AppStorage("expandedShowMetadata") private var showMetadata = true
  @AppStorage("expandedInteractionEnabled") var interactionEnabled = false
  @AppStorage(DashboardSettings.safeModeKey) var safeMode = true
  @State var consecutiveFailures = 0
  @State var pageConnection: CDPPageConnection?
  @State var fallbackInputClient: CDPClient?
  @State var isScreencasting = false
  @State var isSnapshotFallback = false
  @State var frameMode: ExpandedFrameMode = .waiting
  @State var targetMonitorMode: ExpandedTargetMonitorMode = .connecting
  @State var lastTargetRefreshError: String?
  @State var lastCDPError: String?
  @State var currentFrameImage: NSImage?
  @State var currentFrameResult: CDPClient.ScreenshotResult?
  @State var framesSinceLastPersist = 0
  @State var hasPersistedScreencastFrame = false
  @State var lastLocalInteractionAt: Date?
  @State var showsAgentActivityWarning = false
  @State var agentActivityDismissTask: Task<Void, Never>?
  @State var recordingWriter: ExpandedRecordingWriter?
  @State var isRecording = false
  @State var isFinishingRecording = false
  @State var recordingFrameCount = 0
  @State var recordingError: String?
  @State var lastRecordingURL: URL?
  @State var lastRecordingExportURL: URL?
  @State var isExportingRecording = false
  @State var recordingExportError: String?
  @State var smokeNavigationResult: String?
  @State var smokeNavigationError: String?
  private var selectedTargetKey: String {
    session.selectedTargetId ?? "default"
  }

  /// Show a warning after this many consecutive CDP failures.
  let failureWarningThreshold = 5

  var body: some View {
    VStack(spacing: 0) {
      SessionInfoBar(
        session: session,
        onBack: backAction,
        onDetach: detachedWindowAction,
        onNavigate: navigate,
        canRecord: canRecord,
        isRecording: isRecording,
        isFinishingRecording: isFinishingRecording,
        recordingFrameCount: recordingFrameCount,
        recordingError: recordingError,
        lastRecordingURL: lastRecordingURL,
        lastRecordingExportURL: lastRecordingExportURL,
        isExportingRecording: isExportingRecording,
        recordingExportError: recordingExportError,
        onToggleRecording: toggleRecording,
        onExportRecording: exportLastRecording,
        onEnableControlMode: enableControlMode,
        onReturnToSafeMode: returnToSafeMode,
        onDismissRecordingError: { recordingError = nil },
        onDismissRecordingExportError: { recordingExportError = nil },
        showMetadata: $showMetadata,
        interactionEnabled: interactionModeBinding,
        safeModeEnabled: safeMode,
        connectionSummary: connectionSummary
      )

      Divider()

      HStack(spacing: 0) {
        screenshotArea
        if showMetadata {
          Divider()
          SessionMetadataPanel(
            session: session,
            frameMode: frameMode,
            targetMonitorMode: targetMonitorMode,
            lastCDPError: lastCDPError,
            lastTargetError: lastTargetRefreshError
          )
          .transition(.move(edge: .trailing))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: showMetadata)
    }
    .task(id: "\(session.sessionId):\(selectedTargetKey)") {
      await streamOrFallbackLoop()
    }
    .task(id: session.sessionId) {
      await targetRefreshLoop()
    }
    .task(id: smokeCommandSignature) {
      await runSmokeNavigationIfNeeded()
    }
    .onAppear {
      reportSmokeExpandedReadiness()
    }
    .onChange(of: expandedReadinessSignature) {
      reportSmokeExpandedReadiness()
    }
  }

  // MARK: - Screenshot Area

  private var screenshotArea: some View {
    Group {
      if session.cdpPort <= 0 {
        ExpandedNoCDPState()
      } else if let nsImage = currentFrameImage ?? session.screenshotImage {
        ZStack(alignment: .topTrailing) {
          InteractiveScreenshotSurface(
            image: nsImage,
            interactionEnabled: effectiveInteractionEnabled,
            onClick: dispatchClick,
            onScroll: dispatchScroll,
            onKeyPress: dispatchKeyPress
          )
          .padding(20)

          badgeStack
            .padding(28)
        }
      } else if consecutiveFailures >= failureWarningThreshold {
        ExpandedConnectionFailedState(cdpPort: session.cdpPort)
      } else {
        ExpandedLoadingSnapshotState()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var badgeStack: some View {
    VStack(alignment: .trailing, spacing: 6) {
      ExpandedRefreshBadge(frameMode: frameMode)

      if effectiveInteractionEnabled {
        ExpandedInteractionBadge()
      }

      if showsAgentActivityWarning {
        ExpandedAgentActivityBadge()
      }

      if isRecording {
        ExpandedRecordingBadge(frameCount: recordingFrameCount)
      }

      if consecutiveFailures >= failureWarningThreshold {
        ExpandedConnectionWarningBadge()
      }
    }
  }

  private func dispatchClick(_ point: CGPoint) {
    guard effectiveInteractionEnabled, session.cdpPort > 0 else { return }
    noteLocalInteraction()
    Task {
      do {
        if let pageConnection {
          try await pageConnection.dispatchMouseClick(x: point.x, y: point.y)
        } else {
          try await currentFallbackInputClient().dispatchMouseClick(
            x: point.x,
            y: point.y,
            targetId: session.selectedTargetId
          )
        }
      } catch {
        lastCDPError = error.localizedDescription
        logger.warning("Mouse click dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  private func dispatchScroll(_ point: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
    guard effectiveInteractionEnabled, session.cdpPort > 0 else { return }
    noteLocalInteraction()
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
            deltaY: Double(-deltaY),
            targetId: session.selectedTargetId
          )
        }
      } catch {
        lastCDPError = error.localizedDescription
        logger.warning("Mouse wheel dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  private func dispatchKeyPress(_ input: CDPClient.KeyEventInput) {
    guard effectiveInteractionEnabled, session.cdpPort > 0 else { return }
    noteLocalInteraction()
    Task {
      do {
        if let pageConnection {
          try await pageConnection.dispatchKeyPress(input)
        } else {
          try await currentFallbackInputClient().dispatchKeyPress(
            input,
            targetId: session.selectedTargetId
          )
        }
      } catch {
        lastCDPError = error.localizedDescription
        logger.warning("Key dispatch failed: \(error.localizedDescription)")
      }
    }
  }

  func navigate(to rawURL: String) async throws -> String {
    guard !appState.isSafeMode else {
      throw SafeModeBlockedError()
    }
    guard session.cdpPort > 0 else {
      throw CDPClient.CDPError.noPages
    }
    noteLocalInteraction()

    let normalizedURL: String
    if let pageConnection {
      normalizedURL = try await pageConnection.navigate(to: rawURL)
    } else {
      normalizedURL = try await currentFallbackInputClient().navigate(
        to: rawURL,
        targetId: session.selectedTargetId
      )
    }

    session.lastURL = normalizedURL
    session.status = SessionRecord.deriveStatus(from: normalizedURL)
    session.lastActivityAt = Date()
    appState.saveSessionChanges()
    return normalizedURL
  }

  private func currentFallbackInputClient() -> CDPClient {
    if let fallbackInputClient { return fallbackInputClient }
    let client = CDPClient(port: session.cdpPort)
    fallbackInputClient = client
    return client
  }

  private func noteLocalInteraction() {
    lastLocalInteractionAt = Date()
  }

  func detectAgentActivityIfNeeded(
    previous: CDPClient.ScreenshotResult?,
    new: CDPClient.ScreenshotResult
  ) {
    guard
      ExpandedAgentActivityHeuristic.shouldShowWarning(
        interactionEnabled: effectiveInteractionEnabled,
        previousURL: previous?.url,
        previousTitle: previous?.title,
        newURL: new.url,
        newTitle: new.title,
        lastLocalInteractionAt: lastLocalInteractionAt
      )
    else { return }

    showsAgentActivityWarning = true
    agentActivityDismissTask?.cancel()
    agentActivityDismissTask = Task {
      do {
        try await Task.sleep(for: ExpandedAgentActivityHeuristic.warningDuration)
      } catch { return }
      showsAgentActivityWarning = false
      agentActivityDismissTask = nil
    }
  }

}

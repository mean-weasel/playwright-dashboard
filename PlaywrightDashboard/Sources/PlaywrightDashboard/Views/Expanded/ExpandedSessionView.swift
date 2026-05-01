import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) var appState
  let session: SessionRecord
  @AppStorage("expandedShowMetadata") private var showMetadata = true
  @AppStorage("expandedInteractionEnabled") private var interactionEnabled = false
  @State var consecutiveFailures = 0
  @State var pageConnection: CDPPageConnection?
  @State var fallbackInputClient: CDPClient?
  @State var isScreencasting = false
  @State var isSnapshotFallback = false
  @State var frameMode: ExpandedFrameMode = .waiting
  @State var targetMonitorMode: ExpandedTargetMonitorMode = .connecting
  @State var lastTargetRefreshError: String?
  @State var lastCDPError: String?
  @State var frameCountSinceSave = 0
  private var selectedTargetKey: String {
    session.selectedTargetId ?? "default"
  }

  /// Show a warning after this many consecutive CDP failures.
  let failureWarningThreshold = 5

  var body: some View {
    VStack(spacing: 0) {
      SessionInfoBar(
        session: session,
        onBack: { appState.selectedSessionId = nil },
        onNavigate: navigate,
        showMetadata: $showMetadata,
        interactionEnabled: $interactionEnabled,
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
  }

  // MARK: - Screenshot Area

  private var screenshotArea: some View {
    Group {
      if session.cdpPort <= 0 {
        ExpandedNoCDPState()
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
            frameMode: frameMode
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
        ExpandedConnectionFailedState(cdpPort: session.cdpPort)
      } else {
        ExpandedLoadingSnapshotState()
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
    guard interactionEnabled, session.cdpPort > 0 else { return }
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

  private func navigate(to rawURL: String) async throws -> String {
    guard session.cdpPort > 0 else {
      throw CDPClient.CDPError.noPages
    }

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

}

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

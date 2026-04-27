import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  @AppStorage("expandedShowMetadata") private var showMetadata = true
  @State private var consecutiveFailures = 0

  /// Show a warning after this many consecutive CDP failures (~7.5 seconds).
  private let failureWarningThreshold = 5

  var body: some View {
    VStack(spacing: 0) {
      SessionInfoBar(
        session: session,
        onBack: { appState.selectedSessionId = nil },
        showMetadata: $showMetadata
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
      await fastRefreshLoop()
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
      } else if let data = session.lastScreenshot, let nsImage = NSImage(data: data) {
        ZStack(alignment: .topTrailing) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(20)

          if consecutiveFailures >= failureWarningThreshold {
            connectionWarning
              .padding(28)
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
          Text("Connecting to browser...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var connectionWarning: some View {
    Label("Connection lost", systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.orange.opacity(0.15))
      .foregroundStyle(.orange)
      .clipShape(Capsule())
  }

  // MARK: - Fast Refresh

  /// Polls CDP for a fresh screenshot every 1.5s while this session is displayed.
  /// The `.task(id: session.sessionId)` modifier cancels and restarts this loop
  /// when the user switches to a different session.
  private func fastRefreshLoop() async {
    guard session.cdpPort > 0 else { return }
    let client = CDPClient(port: session.cdpPort)

    while !Task.isCancelled {
      do {
        let result = try await client.captureScreenshot(quality: 60)
        session.updateFromScreenshot(result)
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
        try await Task.sleep(for: .seconds(1.5))
      } catch { break }
    }
  }
}

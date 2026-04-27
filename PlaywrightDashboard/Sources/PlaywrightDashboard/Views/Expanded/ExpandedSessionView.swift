import OSLog
import SwiftUI

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ExpandedSessionView")

struct ExpandedSessionView: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  @AppStorage("expandedShowMetadata") private var showMetadata = true

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
    }
    .task(id: session.sessionId) {
      await fastRefreshLoop()
    }
  }

  // MARK: - Screenshot Area

  private var screenshotArea: some View {
    Group {
      if let data = session.lastScreenshot, let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(20)
      } else {
        VStack(spacing: 12) {
          ProgressView()
            .controlSize(.large)
          Text("Waiting for screenshot...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: - Fast Refresh

  private func fastRefreshLoop() async {
    guard session.cdpPort > 0 else { return }
    let client = CDPClient(port: session.cdpPort)

    while !Task.isCancelled {
      do {
        let result = try await client.captureScreenshot(quality: 60)
        session.lastScreenshot = result.jpeg
        session.lastURL = result.url
        session.lastTitle = result.title
        session.lastActivityAt = Date()
        session.status = (result.url != nil && result.url != "about:blank") ? .active : .idle
      } catch is CancellationError {
        break
      } catch {
        logger.debug(
          "Fast refresh failed on port \(session.cdpPort): \(error.localizedDescription)"
        )
      }

      do {
        try await Task.sleep(for: .seconds(1.5))
      } catch { break }
    }
  }
}

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "ScreenshotService")

/// Periodically captures CDP screenshots for all sessions with a valid port.
/// Updates SessionRecord.lastScreenshot, lastURL, lastTitle, and status.
@Observable
@MainActor
final class ScreenshotService {
  typealias StaleThresholdProvider = @MainActor () -> TimeInterval

  /// Interval between capture cycles.
  private var interval: Duration {
    DashboardSettings.thumbnailRefreshDuration()
  }
  /// How long since last activity before marking a session stale.
  /// 0 means stale detection is disabled ("Never").
  private var staleThreshold: TimeInterval {
    staleThresholdProvider()
  }
  private var task: Task<Void, Never>?
  private var clients: [Int: any ScreenshotCapturing] = [:]
  private let clientFactory: @MainActor (Int) -> any ScreenshotCapturing
  private let staleThresholdProvider: StaleThresholdProvider

  init(
    clientFactory: @escaping @MainActor (Int) -> any ScreenshotCapturing = { CDPClient(port: $0) },
    staleThresholdProvider: @escaping StaleThresholdProvider = {
      TimeInterval(UserDefaults.standard.integer(forKey: "staleThresholdSeconds"))
    }
  ) {
    self.clientFactory = clientFactory
    self.staleThresholdProvider = staleThresholdProvider
  }

  /// Start periodic screenshot capture.
  func start(appState: AppState) {
    guard task == nil else { return }

    task = Task { [weak self, weak appState] in
      while !Task.isCancelled {
        guard let self, let appState else { return }
        await self.captureAll(appState: appState)
        do {
          try await Task.sleep(for: self.interval)
        } catch { break }
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    clients.removeAll()
  }

  // MARK: - Private

  func captureAll(appState: AppState) async {
    let sessions = appState.sessions
    let selectedSessionId = appState.selectedSessionId

    // Gather targets on the main actor, skipping the session displayed in expanded view
    // (its dedicated fast-refresh loop handles captures to avoid dual-writer conflicts)
    let targets: [(sessionId: String, port: Int, targetId: String?)] =
      sessions
      .filter {
        $0.cdpPort > 0 && $0.status != .closed && $0.status != .closing
          && $0.sessionId != selectedSessionId
      }
      .map { ($0.sessionId, $0.cdpPort, $0.selectedTargetId) }

    // Capture screenshots concurrently off the main actor
    let results = await withTaskGroup(
      of: (String, CDPClient.ScreenshotResult?).self
    ) { group in
      for target in targets {
        let client = getClient(for: target.port)
        group.addTask {
          do {
            let result = try await client.captureScreenshot(
              quality: DashboardSettings.thumbnailQuality(),
              targetId: target.targetId)
            return (target.sessionId, result)
          } catch is CancellationError {
            return (target.sessionId, nil)
          } catch {
            logger.debug(
              "CDP capture failed for port \(target.port): \(error.localizedDescription)")
            return (target.sessionId, nil)
          }
        }
      }

      var collected: [(String, CDPClient.ScreenshotResult?)] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // Apply results back on the main actor
    var didUpdateSession = false
    for (sessionId, result) in results {
      guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
        continue
      }
      guard session.status != .closed else { continue }

      if let result {
        session.updateFromScreenshot(result)
        markStaleIfNeeded(session)
        didUpdateSession = true
      } else {
        // CDP connection failed — mark stale if inactive long enough
        if markStaleIfNeeded(session) {
          didUpdateSession = true
        }
      }
    }

    if didUpdateSession {
      appState.saveSessionChanges()
    }
  }

  private func getClient(for port: Int) -> any ScreenshotCapturing {
    if let existing = clients[port] {
      return existing
    }
    let client = clientFactory(port)
    clients[port] = client
    return client
  }

  @discardableResult
  private func markStaleIfNeeded(_ session: SessionRecord) -> Bool {
    session.markStaleIfInactive(threshold: staleThreshold)
  }
}

protocol ScreenshotCapturing: Sendable {
  func captureScreenshot(quality: Int, targetId: String?) async throws -> CDPClient.ScreenshotResult
}

extension CDPClient: ScreenshotCapturing {}

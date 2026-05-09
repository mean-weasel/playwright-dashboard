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
  private var backoffByPort: [Int: CaptureBackoff] = [:]
  private let clientFactory: @MainActor (Int) -> any ScreenshotCapturing
  private let staleThresholdProvider: StaleThresholdProvider
  private let maxConcurrentCaptures: Int
  private let nowProvider: @MainActor () -> Date
  private(set) var skippedForBackoffCount = 0
  private(set) var captureFailureCount = 0

  var activeClientCount: Int {
    clients.count
  }

  var backoffPortCount: Int {
    backoffByPort.count
  }

  init(
    clientFactory: @escaping @MainActor (Int) -> any ScreenshotCapturing = { CDPClient(port: $0) },
    staleThresholdProvider: @escaping StaleThresholdProvider = {
      TimeInterval(UserDefaults.standard.integer(forKey: "staleThresholdSeconds"))
    },
    maxConcurrentCaptures: Int = 4,
    nowProvider: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.clientFactory = clientFactory
    self.staleThresholdProvider = staleThresholdProvider
    self.maxConcurrentCaptures = max(1, maxConcurrentCaptures)
    self.nowProvider = nowProvider
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
    backoffByPort.removeAll()
  }

  // MARK: - Private

  func captureAll(appState: AppState) async {
    let sessions = appState.sessions
    let selectedSessionId = appState.selectedSessionId
    let now = nowProvider()

    // Gather targets on the main actor, skipping the session displayed in expanded view
    // (its dedicated fast-refresh loop handles captures to avoid dual-writer conflicts)
    let candidateTargets: [(sessionId: String, port: Int, targetId: String?)] =
      sessions
      .filter {
        $0.cdpPort > 0 && $0.status != .closed && $0.status != .closing
          && $0.sessionId != selectedSessionId
      }
      .map { ($0.sessionId, $0.cdpPort, $0.selectedTargetId) }

    evictStaleClients(keeping: Set(candidateTargets.map(\.port)))

    let targets =
      candidateTargets
      .filter { target in
        guard let backoff = backoffByPort[target.port], backoff.retryAfter > now else {
          return true
        }
        skippedForBackoffCount += 1
        return false
      }

    // Capture screenshots concurrently off the main actor
    var results: [(sessionId: String, port: Int, result: CDPClient.ScreenshotResult?)] = []
    for batchStart in stride(from: 0, to: targets.count, by: maxConcurrentCaptures) {
      let batch = Array(
        targets[batchStart..<min(batchStart + maxConcurrentCaptures, targets.count)]
      )
      let batchResults = await withTaskGroup(
        of: (String, Int, CDPClient.ScreenshotResult?).self
      ) { group in
        for target in batch {
          let client = getClient(for: target.port)
          group.addTask {
            do {
              let result = try await client.captureScreenshot(
                quality: DashboardSettings.thumbnailQuality(),
                targetId: target.targetId)
              return (target.sessionId, target.port, result)
            } catch is CancellationError {
              return (target.sessionId, target.port, nil)
            } catch {
              logger.debug(
                "CDP capture failed for port \(target.port): \(error.localizedDescription)")
              return (target.sessionId, target.port, nil)
            }
          }
        }

        var collected: [(String, Int, CDPClient.ScreenshotResult?)] = []
        for await result in group {
          collected.append(result)
        }
        return collected
      }
      results.append(contentsOf: batchResults)
    }

    // Apply results back on the main actor
    var didUpdateSession = false
    for (sessionId, port, result) in results {
      guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
        continue
      }
      guard session.status != .closed else { continue }

      if let result {
        backoffByPort[port] = nil
        session.updateFromScreenshot(result)
        markStaleIfNeeded(session)
        didUpdateSession = true
      } else {
        recordCaptureFailure(port: port, now: now)
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

  private func evictStaleClients(keeping activePorts: Set<Int>) {
    clients = clients.filter { activePorts.contains($0.key) }
    backoffByPort = backoffByPort.filter { activePorts.contains($0.key) }
  }

  private func recordCaptureFailure(port: Int, now: Date) {
    captureFailureCount += 1
    let previousFailures = backoffByPort[port]?.failureCount ?? 0
    let failureCount = previousFailures + 1
    let delay: TimeInterval
    switch failureCount {
    case 1:
      delay = 5
    case 2:
      delay = 15
    case 3:
      delay = 30
    default:
      delay = 60
    }
    backoffByPort[port] = CaptureBackoff(
      failureCount: failureCount,
      retryAfter: now.addingTimeInterval(delay)
    )
  }

  @discardableResult
  private func markStaleIfNeeded(_ session: SessionRecord) -> Bool {
    session.markStaleIfInactive(threshold: staleThreshold)
  }
}

private struct CaptureBackoff {
  let failureCount: Int
  let retryAfter: Date
}

protocol ScreenshotCapturing: Sendable {
  func captureScreenshot(quality: Int, targetId: String?) async throws -> CDPClient.ScreenshotResult
}

extension CDPClient: ScreenshotCapturing {}

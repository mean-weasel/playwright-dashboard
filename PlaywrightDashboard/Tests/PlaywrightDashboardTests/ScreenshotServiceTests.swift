import Foundation
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("ScreenshotService", .serialized)
struct ScreenshotServiceTests {

  @Test("skips selected expanded session")
  func skipsSelectedExpandedSession() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["expanded": 9301, "thumbnail": 9302],
      outcomesByPort: [
        9301: .success(jpeg: Data([0x01]), url: "http://expanded.test", title: "Expanded"),
        9302: .success(jpeg: Data([0x02]), url: "http://thumbnail.test", title: "Thumbnail"),
      ]
    )
    defer { fixture.appState.stopSync() }
    fixture.appState.selectedSessionId = "expanded"

    await fixture.service.captureAll(appState: fixture.appState)

    let expanded = try #require(fixture.session("expanded"))
    let thumbnail = try #require(fixture.session("thumbnail"))
    #expect(await fixture.recorder.capturedPorts() == [9302])
    #expect(expanded.lastScreenshot == nil)
    #expect(thumbnail.lastScreenshot == Data([0x02]))
    #expect(thumbnail.lastURL == "http://thumbnail.test")
    #expect(fixture.saveCounter.count == 1)
  }

  @Test("updates successful screenshot results")
  func updatesSuccessfulScreenshotResults() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["active": 9311],
      outcomesByPort: [
        9311: .success(jpeg: Data([0xA1, 0xB2]), url: "http://app.test", title: "App")
      ]
    )
    defer { fixture.appState.stopSync() }

    await fixture.service.captureAll(appState: fixture.appState)

    let session = try #require(fixture.session("active"))
    #expect(session.lastScreenshot == Data([0xA1, 0xB2]))
    #expect(session.lastURL == "http://app.test")
    #expect(session.lastTitle == "App")
    #expect(session.status == .active)
    #expect(fixture.saveCounter.count == 1)
  }

  @Test("passes selected target id to thumbnail capture")
  func passesSelectedTargetIdToThumbnailCapture() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["active": 9315],
      outcomesByPort: [
        9315: .success(jpeg: Data([0xA1]), url: "http://app.test", title: "App")
      ]
    )
    defer { fixture.appState.stopSync() }
    let session = try #require(fixture.session("active"))
    session.selectedTargetId = "target-2"

    await fixture.service.captureAll(appState: fixture.appState)

    let capturedTargets = await fixture.recorder.capturedTargets()
    #expect(capturedTargets.count == 1)
    #expect(capturedTargets.first?.port == 9315)
    #expect(capturedTargets.first?.targetId == "target-2")
  }

  @Test("marks stale after capture failure")
  func marksStaleAfterCaptureFailure() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["old": 9321],
      outcomesByPort: [9321: .failure],
      staleThreshold: 60
    )
    defer { fixture.appState.stopSync() }
    let session = try #require(fixture.session("old"))
    session.status = .active
    session.lastActivityAt = Date().addingTimeInterval(-120)

    await fixture.service.captureAll(appState: fixture.appState)

    #expect(await fixture.recorder.capturedPorts() == [9321])
    #expect(session.status == .stale)
    #expect(session.lastScreenshot == nil)
    #expect(fixture.saveCounter.count == 1)
  }

  @Test("ignores closed and closing sessions")
  func ignoresClosedAndClosingSessions() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["closed": 9331, "closing": 9332, "open": 9333],
      outcomesByPort: [
        9331: .success(jpeg: Data([0x01]), url: "http://closed.test", title: "Closed"),
        9332: .success(jpeg: Data([0x02]), url: "http://closing.test", title: "Closing"),
        9333: .success(jpeg: Data([0x03]), url: "http://open.test", title: "Open"),
      ]
    )
    defer { fixture.appState.stopSync() }
    let closed = try #require(fixture.session("closed"))
    let closing = try #require(fixture.session("closing"))
    let open = try #require(fixture.session("open"))
    closed.status = .closed
    closing.status = .closing

    await fixture.service.captureAll(appState: fixture.appState)

    #expect(await fixture.recorder.capturedPorts() == [9333])
    #expect(closed.lastScreenshot == nil)
    #expect(closing.lastScreenshot == nil)
    #expect(open.lastScreenshot == Data([0x03]))
    #expect(fixture.saveCounter.count == 1)
  }

  @Test("saves only when changes occur")
  func savesOnlyWhenChangesOccur() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["unchanged": 9341],
      outcomesByPort: [9341: .failure],
      staleThreshold: 0
    )
    defer { fixture.appState.stopSync() }
    let session = try #require(fixture.session("unchanged"))
    session.status = .active
    session.lastActivityAt = Date().addingTimeInterval(-120)

    await fixture.service.captureAll(appState: fixture.appState)

    #expect(await fixture.recorder.capturedPorts() == [9341])
    #expect(session.status == .active)
    #expect(session.lastScreenshot == nil)
    #expect(fixture.saveCounter.count == 0)
  }

  @Test("handles multiple sessions in one capture cycle")
  func handlesMultipleSessions() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["first": 9351, "second": 9352, "stale": 9353],
      outcomesByPort: [
        9351: .success(jpeg: Data([0x11]), url: "http://first.test", title: "First"),
        9352: .success(jpeg: Data([0x22]), url: "about:blank", title: ""),
        9353: .failure,
      ],
      staleThreshold: 60
    )
    defer { fixture.appState.stopSync() }
    let stale = try #require(fixture.session("stale"))
    stale.status = .idle
    stale.lastActivityAt = Date().addingTimeInterval(-120)

    await fixture.service.captureAll(appState: fixture.appState)

    let first = try #require(fixture.session("first"))
    let second = try #require(fixture.session("second"))
    #expect(Set(await fixture.recorder.capturedPorts()) == [9351, 9352, 9353])
    #expect(first.lastScreenshot == Data([0x11]))
    #expect(first.status == .active)
    #expect(second.lastScreenshot == Data([0x22]))
    #expect(second.status == .idle)
    #expect(stale.status == .stale)
    #expect(fixture.saveCounter.count == 1)
  }

  @Test("backs off failed ports and skips them until retry time")
  func backsOffFailedPorts() async throws {
    let clock = DateBox(Date(timeIntervalSince1970: 1_000))
    let fixture = try await makeFixture(
      portsBySessionId: ["flaky": 9361],
      outcomesByPort: [9361: .failure],
      nowProvider: { clock.now }
    )
    defer { fixture.appState.stopSync() }

    await fixture.service.captureAll(appState: fixture.appState)
    await fixture.service.captureAll(appState: fixture.appState)

    #expect(await fixture.recorder.capturedPorts() == [9361])
    #expect(fixture.service.captureFailureCount == 1)
    #expect(fixture.service.skippedForBackoffCount == 1)
    #expect(fixture.service.backoffPortCount == 1)

    clock.now = Date(timeIntervalSince1970: 1_006)
    await fixture.service.captureAll(appState: fixture.appState)

    #expect(await fixture.recorder.capturedPorts() == [9361, 9361])
    #expect(fixture.service.captureFailureCount == 2)
  }

  @Test("evicts clients for ports no longer targeted")
  func evictsStaleClients() async throws {
    let fixture = try await makeFixture(
      portsBySessionId: ["open": 9371],
      outcomesByPort: [
        9371: .success(jpeg: Data([0x71]), url: "http://open.test", title: "Open")
      ]
    )
    defer { fixture.appState.stopSync() }

    await fixture.service.captureAll(appState: fixture.appState)
    #expect(fixture.service.activeClientCount == 1)

    let session = try #require(fixture.session("open"))
    session.status = .closed
    await fixture.service.captureAll(appState: fixture.appState)

    #expect(fixture.service.activeClientCount == 0)
  }

  private func makeFixture(
    portsBySessionId: [String: Int],
    outcomesByPort: [Int: CaptureOutcome],
    staleThreshold: TimeInterval = 300,
    maxConcurrentCaptures: Int = 4,
    nowProvider: @escaping @MainActor () -> Date = { Date() }
  ) async throws -> ScreenshotServiceFixture {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(
      files: try portsBySessionId.sorted(by: { $0.key < $1.key })
        .map { sessionId, port in
          try harness.writeSession(
            name: sessionId,
            workspace: harness.workspace(sessionId),
            port: port
          )
        })
    let saveCounter = SaveCounter()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      modelContextSaver: { _ in saveCounter.count += 1 }
    )
    appState.startSync(modelContext: harness.context)
    await appState.performSync()

    let recorder = CaptureRecorder()
    let service = ScreenshotService(
      clientFactory: { port in
        FakeScreenshotClient(
          port: port,
          outcome: outcomesByPort[port] ?? .failure,
          recorder: recorder
        )
      },
      staleThresholdProvider: { staleThreshold },
      maxConcurrentCaptures: maxConcurrentCaptures,
      nowProvider: nowProvider
    )

    return ScreenshotServiceFixture(
      harness: harness,
      appState: appState,
      service: service,
      recorder: recorder,
      saveCounter: saveCounter
    )
  }
}

@MainActor
private struct ScreenshotServiceFixture {
  let harness: TestSessionHarness
  let appState: AppState
  let service: ScreenshotService
  let recorder: CaptureRecorder
  let saveCounter: SaveCounter

  func session(_ sessionId: String) -> SessionRecord? {
    appState.sessions.first { $0.sessionId == sessionId }
  }
}

@MainActor
private final class SaveCounter {
  var count = 0
}

private enum CaptureOutcome: Sendable {
  case success(jpeg: Data, url: String?, title: String?)
  case failure
}

private enum ScreenshotServiceTestError: Error {
  case captureFailed
}

private actor CaptureRecorder {
  private var targets: [(port: Int, targetId: String?)] = []

  func record(port: Int, targetId: String?) {
    targets.append((port, targetId))
  }

  func capturedPorts() -> [Int] {
    targets.map(\.port).sorted()
  }

  func capturedTargets() -> [(port: Int, targetId: String?)] {
    targets.sorted { lhs, rhs in
      if lhs.port != rhs.port { return lhs.port < rhs.port }
      return (lhs.targetId ?? "") < (rhs.targetId ?? "")
    }
  }
}

@MainActor
private final class DateBox {
  var now: Date

  init(_ now: Date) {
    self.now = now
  }
}

private actor FakeScreenshotClient: ScreenshotCapturing {
  let port: Int
  let outcome: CaptureOutcome
  let recorder: CaptureRecorder

  init(port: Int, outcome: CaptureOutcome, recorder: CaptureRecorder) {
    self.port = port
    self.outcome = outcome
    self.recorder = recorder
  }

  func captureScreenshot(quality: Int, targetId: String?) async throws -> CDPClient.ScreenshotResult
  {
    await recorder.record(port: port, targetId: targetId)
    switch outcome {
    case .success(let jpeg, let url, let title):
      return CDPClient.ScreenshotResult(jpeg: jpeg, url: url, title: title)
    case .failure:
      throw ScreenshotServiceTestError.captureFailed
    }
  }
}

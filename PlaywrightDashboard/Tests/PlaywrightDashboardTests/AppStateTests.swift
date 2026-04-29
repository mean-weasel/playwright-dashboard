import Foundation
import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("AppState")
struct AppStateTests {

  @Test("startSync begins watching and publishes sessions without opening popover")
  func startSyncPublishesSessions() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "smoke-session", workspace: harness.workspace("smoke-session"))
    ])
    let watchState = WatchState()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      startWatching: { watchState.startCount += 1 },
      stopWatching: { watchState.stopCount += 1 },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)
    appState.startSync(modelContext: harness.context)

    #expect(watchState.startCount == 1)
    #expect(appState.sessions.map(\.sessionId) == ["smoke-session"])

    appState.stopSync()
    #expect(watchState.stopCount == 1)
  }

  @Test("stopSync allows a later restart")
  func stopSyncAllowsRestart() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "first-session", workspace: harness.workspace("first-session"))
    ])
    let watchState = WatchState()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      startWatching: { watchState.startCount += 1 },
      stopWatching: { watchState.stopCount += 1 },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)
    appState.stopSync()

    provider.files = [
      try harness.writeSession(
        name: "second-session", workspace: harness.workspace("second-session"))
    ]
    appState.startSync(modelContext: harness.context)

    #expect(watchState.startCount == 2)
    #expect(watchState.stopCount == 1)
    #expect(appState.sessions.map(\.sessionId).contains("second-session"))
  }

  @Test("session commands save user changes")
  func sessionCommandsSaveUserChanges() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "first-session", workspace: harness.workspace("first-session")),
      try harness.writeSession(
        name: "second-session", workspace: harness.workspace("second-session")),
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)

    guard let first = appState.sessions.first(where: { $0.sessionId == "first-session" }),
      let second = appState.sessions.first(where: { $0.sessionId == "second-session" })
    else {
      Issue.record("Expected both test sessions")
      return
    }
    let originalFirstOrder = first.gridOrder
    let originalSecondOrder = second.gridOrder

    appState.rename(first, to: "  Primary Session  ")
    #expect(appState.reorder(sourceId: first.sessionId, targetId: second.sessionId))
    appState.selectedSessionId = first.sessionId
    appState.close(first, byUser: true)

    let saved = try harness.context.fetch(FetchDescriptor<SessionRecord>())
    let savedFirst = saved.first { $0.sessionId == "first-session" }
    let savedSecond = saved.first { $0.sessionId == "second-session" }

    #expect(savedFirst?.customName == "Primary Session")
    #expect(savedFirst?.status == .closed)
    #expect(savedFirst?.userClosed == true)
    #expect(appState.selectedSessionId == nil)
    #expect(savedFirst?.gridOrder == originalSecondOrder)
    #expect(savedSecond?.gridOrder == originalFirstOrder)
  }

  @Test("closeStaleSessions clears a selected stale session")
  func closeStaleSessionsClearsSelection() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "stale-session", workspace: harness.workspace("stale-session"))
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)
    guard let stale = appState.sessions.first else {
      Issue.record("Expected test session")
      return
    }

    stale.status = .stale
    appState.selectedSessionId = stale.sessionId
    appState.closeStaleSessions()

    #expect(stale.status == .closed)
    #expect(stale.userClosed == true)
    #expect(appState.selectedSessionId == nil)
  }

  @Test("clearClosedSessions deletes closed records")
  func clearClosedSessionsDeletesClosedRecords() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "open-session", workspace: harness.workspace("open-session")),
      try harness.writeSession(
        name: "closed-session", workspace: harness.workspace("closed-session")),
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)
    guard let closed = appState.sessions.first(where: { $0.sessionId == "closed-session" }) else {
      Issue.record("Expected closed-session")
      return
    }
    appState.close(closed, byUser: true)

    appState.clearClosedSessions()

    let savedIds = try harness.context.fetch(FetchDescriptor<SessionRecord>()).map(\.sessionId)
    #expect(savedIds == ["open-session"])
    #expect(appState.sessions.map(\.sessionId) == ["open-session"])
  }

  @Test("closeAndTerminate archives locally and invokes terminator")
  func closeAndTerminateInvokesTerminator() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "close-me", workspace: harness.workspace("close-me"))
    ])
    let recorder = CommandRecorder()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { sessionId in
        await recorder.record(sessionId)
        return ProcessResult(exitStatus: 0, output: "")
      }
    )

    appState.startSync(modelContext: harness.context)
    guard let session = appState.sessions.first else {
      Issue.record("Expected test session")
      return
    }

    appState.closeAndTerminate(session)
    try await Task.sleep(for: .milliseconds(50))

    #expect(session.status == .closed)
    #expect(session.userClosed == true)
    #expect(await recorder.commands == [["-s=close-me", "close"]])
    #expect(appState.sessionTerminationErrors["close-me"] == nil)
  }

  @Test("closeAndTerminate records terminator errors")
  func closeAndTerminateRecordsErrors() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "fail-close", workspace: harness.workspace("fail-close"))
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { _ in
        ProcessResult(exitStatus: 2, output: "missing session")
      }
    )

    appState.startSync(modelContext: harness.context)
    guard let session = appState.sessions.first else {
      Issue.record("Expected test session")
      return
    }

    appState.closeAndTerminate(session)
    try await Task.sleep(for: .milliseconds(50))

    #expect(appState.sessionTerminationErrors["fail-close"]?.contains("missing session") == true)
  }

  @Test("dismissTerminationError removes one recorded error")
  func dismissTerminationError() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "fail-close", workspace: harness.workspace("fail-close"))
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { _ in
        ProcessResult(exitStatus: 2, output: "missing session")
      }
    )

    appState.startSync(modelContext: harness.context)
    let session = try #require(appState.sessions.first)
    appState.closeAndTerminate(session)
    try await Task.sleep(for: .milliseconds(50))

    appState.dismissTerminationError(sessionId: "fail-close")

    #expect(appState.sessionTerminationErrors.isEmpty)
  }

  @Test("dismissAllTerminationErrors clears every recorded error")
  func dismissAllTerminationErrors() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "fail-one", workspace: harness.workspace("fail-one")),
      try harness.writeSession(name: "fail-two", workspace: harness.workspace("fail-two")),
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { _ in
        ProcessResult(exitStatus: 2, output: "missing session")
      }
    )

    appState.startSync(modelContext: harness.context)
    for session in appState.sessions {
      appState.closeAndTerminate(session)
    }
    try await Task.sleep(for: .milliseconds(50))

    appState.dismissAllTerminationErrors()

    #expect(appState.sessionTerminationErrors.isEmpty)
  }

  @Test("closeAndTerminateStaleSessions records termination errors")
  func closeAndTerminateStaleSessionsRecordsErrors() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "stale-one", workspace: harness.workspace("stale-one")),
      try harness.writeSession(name: "stale-two", workspace: harness.workspace("stale-two")),
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { _ in
        ProcessResult(exitStatus: 2, output: "missing session")
      }
    )

    appState.startSync(modelContext: harness.context)
    for session in appState.sessions {
      session.status = .stale
    }

    appState.closeAndTerminateStaleSessions()
    try await Task.sleep(for: .milliseconds(50))

    #expect(appState.sessions.allSatisfy { $0.status == .closed })
    #expect(Set(appState.sessionTerminationErrors.keys) == ["stale-one", "stale-two"])
  }

  @Test("saveScreenshot writes JPEG data to the configured directory")
  func saveScreenshotWritesFile() throws {
    let harness = try TestSessionHarness()
    let appState = AppState(
      sessionFileProvider: { [] },
      screenshotDirectoryProvider: { harness.root }
    )
    let session = SessionRecord(
      sessionId: "shot",
      autoLabel: "Shot",
      workspaceDir: harness.workspace("shot"),
      cdpPort: 9222,
      socketPath: "/tmp/shot.sock",
      lastScreenshot: Data([0x01, 0x02, 0x03])
    )

    let savedURL = try #require(appState.saveScreenshot(session))

    #expect(savedURL.deletingLastPathComponent() == harness.root)
    #expect(try Data(contentsOf: savedURL) == Data([0x01, 0x02, 0x03]))
    #expect(appState.lastSavedScreenshotURL == savedURL)
  }

  @MainActor
  private final class WatchState {
    var startCount = 0
    var stopCount = 0
  }

  private actor CommandRecorder {
    private(set) var commands: [[String]] = []

    func record(_ args: [String]) {
      commands.append(args)
    }
  }
}

import Foundation
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

  @MainActor
  private final class WatchState {
    var startCount = 0
    var stopCount = 0
  }
}

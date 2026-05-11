import Foundation
import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("AppState", .serialized)
struct AppStateTests {

  @Test("startSync begins watching and publishes sessions without opening popover")
  func startSyncPublishesSessions() async throws {
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
    await appState.performSync()
    appState.startSync(modelContext: harness.context)
    await appState.performSync()

    #expect(watchState.startCount == 1)
    #expect(appState.sessions.map(\.sessionId) == ["smoke-session"])

    appState.stopSync()
    #expect(watchState.stopCount == 1)
  }

  @Test("stopSync allows a later restart")
  func stopSyncAllowsRestart() async throws {
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
    await appState.performSync()
    appState.stopSync()

    provider.files = [
      try harness.writeSession(
        name: "second-session", workspace: harness.workspace("second-session"))
    ]
    appState.startSync(modelContext: harness.context)
    await appState.performSync()

    #expect(watchState.startCount == 2)
    #expect(watchState.stopCount == 1)
    #expect(appState.sessions.map(\.sessionId).contains("second-session"))
  }

  @Test("session commands save user changes")
  func sessionCommandsSaveUserChanges() async throws {
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
      syncInterval: .seconds(60),
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()

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

  @Test("session command save failures are published and dismissible")
  func sessionCommandSaveFailuresArePublished() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "save-fail", workspace: harness.workspace("save-fail"))
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      modelContextSaver: { _ in throw TestError.saveFailed }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    let session = try #require(appState.sessions.first)

    appState.rename(session, to: "Unsaved Name")

    #expect(appState.lastPersistenceSaveError == "saveFailed")

    appState.dismissPersistenceSaveError()

    #expect(appState.lastPersistenceSaveError == nil)
  }

  @Test("closeStaleSessions clears a selected stale session")
  func closeStaleSessionsClearsSelection() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "stale-session", workspace: harness.workspace("stale-session"))
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
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
  func clearClosedSessionsDeletesClosedRecords() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "open-session", workspace: harness.workspace("open-session")),
      try harness.writeSession(
        name: "closed-session", workspace: harness.workspace("closed-session")),
    ])
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
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

  @Test("startSync publishes session file errors and dismisses them")
  func startSyncPublishesSessionFileErrors() async throws {
    let harness = try TestSessionHarness()
    let malformedFile = harness.root.appendingPathComponent("broken.session")
    try "{ not-json".write(to: malformedFile, atomically: true, encoding: .utf8)
    let appState = AppState(
      sessionFileProvider: { [malformedFile] },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60)
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()

    #expect(appState.sessionFileErrors.keys.contains("broken.session"))

    appState.dismissSessionFileError(filename: "broken.session")

    #expect(appState.sessionFileErrors.isEmpty)
  }

  @Test("startSync publishes and clears automatic sync save failures")
  func startSyncPublishesAutomaticSyncSaveFailures() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "sync-save-fail", workspace: harness.workspace("sync-save-fail"))
    ])
    let saveFailure = SaveFailureSwitch()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionSyncModelContextSaver: { context in
        if saveFailure.shouldFail {
          throw TestError.saveFailed
        }
        try context.save()
      }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()

    #expect(appState.lastPersistenceSaveError == "saveFailed")
    #expect(appState.diagnosticsText().contains("lastPersistenceSaveError: saveFailed"))

    saveFailure.shouldFail = false
    await appState.performSync()

    #expect(appState.lastPersistenceSaveError == nil)
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
      },
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    guard let session = appState.sessions.first else {
      Issue.record("Expected test session")
      return
    }

    appState.closeAndTerminate(session)
    await waitUntil { session.status == .closed }

    #expect(session.status == .closed)
    #expect(session.userClosed == true)
    #expect(await recorder.commands == [["-s=close-me", "close"]])
    #expect(appState.sessionTerminationErrors["close-me"] == nil)
  }

  @Test("safe mode blocks session close and cleanup commands")
  func safeModeBlocksSessionCloseAndCleanupCommands() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(name: "close-me", workspace: harness.workspace("close-me")),
      try harness.writeSession(name: "stale-me", workspace: harness.workspace("stale-me")),
    ])
    let recorder = CommandRecorder()
    let appState = AppState(
      sessionFileProvider: { provider.files },
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      sessionTerminator: SessionTerminator { sessionId in
        await recorder.record(sessionId)
        return ProcessResult(exitStatus: 0, output: "")
      },
      safeModeProvider: { true }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    let closeMe = try #require(appState.sessions.first { $0.sessionId == "close-me" })
    let staleMe = try #require(appState.sessions.first { $0.sessionId == "stale-me" })
    staleMe.status = .stale
    appState.selectedSessionId = closeMe.sessionId

    appState.close(closeMe, byUser: true)
    appState.closeAndTerminate(closeMe)
    appState.retryTerminate(closeMe)
    appState.closeStaleSessions()
    appState.closeAndTerminateStaleSessions()
    try await Task.sleep(for: .milliseconds(50))

    #expect(closeMe.status != .closed)
    #expect(staleMe.status == .stale)
    #expect(appState.selectedSessionId == closeMe.sessionId)
    #expect(await recorder.commands.isEmpty)
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
      },
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    guard let session = appState.sessions.first else {
      Issue.record("Expected test session")
      return
    }

    appState.closeAndTerminate(session)
    await waitUntil { session.status == .closeFailed }

    #expect(session.status == .closeFailed)
    #expect(session.userClosed == false)
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
      },
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    let session = try #require(appState.sessions.first)
    appState.closeAndTerminate(session)
    await waitUntil { session.status == .closeFailed }

    appState.dismissTerminationError(sessionId: "fail-close")

    #expect(appState.sessionTerminationErrors.isEmpty)
    #expect(session.status == .idle)
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
      },
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    for session in appState.sessions {
      appState.closeAndTerminate(session)
    }
    await waitUntil {
      appState.sessionTerminationErrors.keys.contains("fail-one")
        && appState.sessionTerminationErrors.keys.contains("fail-two")
    }

    appState.dismissAllTerminationErrors()

    #expect(appState.sessionTerminationErrors.isEmpty)
    #expect(appState.sessions.allSatisfy { $0.status == .idle })
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
      },
      safeModeProvider: { false }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    for session in appState.sessions {
      session.status = .stale
    }

    appState.closeAndTerminateStaleSessions()
    await waitUntil { Set(appState.sessionTerminationErrors.keys) == ["stale-one", "stale-two"] }

    #expect(appState.sessions.allSatisfy { $0.status == .closeFailed })
    #expect(Set(appState.sessionTerminationErrors.keys) == ["stale-one", "stale-two"])
  }

  @Test("saveScreenshot writes JPEG data to the configured directory")
  func saveScreenshotWritesFile() async throws {
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
    #expect(appState.lastScreenshotSaveError == nil)
  }

  @Test("saveScreenshot sanitizes session id path components")
  func saveScreenshotSanitizesSessionIdPathComponents() async throws {
    let harness = try TestSessionHarness()
    let appState = AppState(
      sessionFileProvider: { [] },
      screenshotDirectoryProvider: { harness.root }
    )
    let session = SessionRecord(
      sessionId: "../admin/session:one",
      autoLabel: "Shot",
      workspaceDir: harness.workspace("shot"),
      cdpPort: 9222,
      socketPath: "/tmp/shot.sock",
      lastScreenshot: Data([0x01, 0x02, 0x03])
    )

    let savedURL = try #require(appState.saveScreenshot(session))

    #expect(savedURL.deletingLastPathComponent() == harness.root)
    #expect(savedURL.lastPathComponent.hasPrefix("---admin-session-one-"))
    #expect(!savedURL.lastPathComponent.contains("/"))
    #expect(
      !FileManager.default.fileExists(
        atPath: harness.root.deletingLastPathComponent().appendingPathComponent("admin").path))
  }

  @Test("saveScreenshot records missing screenshot error")
  func saveScreenshotMissingDataRecordsError() async throws {
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
      socketPath: "/tmp/shot.sock"
    )

    #expect(appState.saveScreenshot(session) == nil)
    #expect(appState.lastScreenshotSaveError == "No screenshot is available to save.")

    appState.dismissScreenshotSaveError()

    #expect(appState.lastScreenshotSaveError == nil)
  }

  @Test("saveScreenshot records write failure")
  func saveScreenshotWriteFailureRecordsError() async throws {
    let harness = try TestSessionHarness()
    let blockedURL = harness.root.appendingPathComponent("not-a-directory")
    try "blocked".write(to: blockedURL, atomically: true, encoding: .utf8)
    let appState = AppState(
      sessionFileProvider: { [] },
      screenshotDirectoryProvider: { blockedURL }
    )
    let session = SessionRecord(
      sessionId: "shot",
      autoLabel: "Shot",
      workspaceDir: harness.workspace("shot"),
      cdpPort: 9222,
      socketPath: "/tmp/shot.sock",
      lastScreenshot: Data([0x01, 0x02, 0x03])
    )

    #expect(appState.saveScreenshot(session) == nil)
    #expect(appState.lastScreenshotSaveError != nil)
  }

  @Test("openCurrentURL opens HTTP URL and clears errors")
  func openCurrentURLOpensHTTPURL() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )
    appState.lastOpenURLError = "Previous error"
    let session = SessionRecord(
      sessionId: "url",
      autoLabel: "URL",
      workspaceDir: "/tmp/url",
      cdpPort: 9222,
      socketPath: "/tmp/url.sock",
      lastURL: "https://example.com/path"
    )

    #expect(appState.openCurrentURL(session))
    #expect(opener.urls.map(\.absoluteString) == ["https://example.com/path"])
    #expect(appState.lastOpenURLError == nil)
  }

  @Test("openCurrentURL rejects unsupported URL schemes")
  func openCurrentURLRejectsUnsupportedSchemes() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )
    let session = SessionRecord(
      sessionId: "url",
      autoLabel: "URL",
      workspaceDir: "/tmp/url",
      cdpPort: 9222,
      socketPath: "/tmp/url.sock",
      lastURL: "file:///tmp/index.html"
    )

    #expect(appState.openCurrentURL(session) == false)
    #expect(opener.urls.isEmpty)
    #expect(appState.lastOpenURLError == "Only HTTP and HTTPS URLs can be opened.")
  }

  @Test("openRecordingDirectory opens local file URL")
  func openRecordingDirectoryOpensLocalFileURL() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )
    appState.lastOpenURLError = "Previous error"
    let url = URL(fileURLWithPath: "/tmp/PlaywrightDashboard Recordings/session")

    #expect(appState.openRecordingDirectory(url))
    #expect(opener.urls == [url])
    #expect(appState.lastOpenURLError == nil)
  }

  @Test("openRecordingDirectory rejects remote URLs")
  func openRecordingDirectoryRejectsRemoteURLs() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )

    #expect(appState.openRecordingDirectory(URL(string: "https://example.com/recording")!) == false)
    #expect(opener.urls.isEmpty)
    #expect(appState.lastOpenURLError == "Recording location is not a local file URL.")
  }

  @Test("openLatestRelease opens GitHub releases page")
  func openLatestReleaseOpensGitHubReleasesPage() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      urlOpener: opener.open
    )

    #expect(appState.openLatestRelease())
    #expect(
      opener.urls.map(\.absoluteString) == [
        "https://github.com/neonwatty/playwright-dashboard/releases/latest"
      ])
    #expect(appState.lastOpenURLError == nil)
  }

  @Test("openCDPInspector opens selected target inspector URL")
  func openCDPInspectorOpensSelectedTargetURL() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )
    let targets = [
      CDPPageTarget(
        id: "page-1",
        type: "page",
        url: "https://example.com/one",
        title: "One",
        webSocketDebuggerUrl: "ws://localhost:9333/devtools/page/page-1"
      ),
      CDPPageTarget(
        id: "page-2",
        type: "page",
        url: "https://example.com/two",
        title: "Two",
        webSocketDebuggerUrl: "ws://localhost:9333/devtools/page/page-2"
      ),
    ]
    let session = SessionRecord(
      sessionId: "cdp",
      autoLabel: "CDP",
      workspaceDir: "/tmp/cdp",
      cdpPort: 9333,
      socketPath: "/tmp/cdp.sock",
      pageTargets: targets,
      selectedTargetId: "page-2"
    )

    #expect(appState.openCDPInspector(session))
    #expect(
      opener.urls.map(\.absoluteString) == [
        "http://localhost:9333/devtools/inspector.html?ws=localhost:9333/devtools/page/page-2"
      ])
  }

  @Test("safe mode blocks CDP inspector URLs")
  func safeModeBlocksCDPInspectorURLs() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { true },
      urlOpener: opener.open
    )
    let session = SessionRecord(
      sessionId: "cdp",
      autoLabel: "CDP",
      workspaceDir: "/tmp/cdp",
      cdpPort: 9333,
      socketPath: "/tmp/cdp.sock"
    )

    #expect(appState.openCDPInspector(session) == false)
    #expect(opener.urls.isEmpty)
    #expect(appState.lastOpenURLError == "Safe mode is enabled. CDP inspector access is disabled.")
  }

  @Test("browser control authorization is per session and does not disable global safe mode")
  func browserControlAuthorizationIsPerSession() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { true },
      urlOpener: opener.open
    )
    let authorized = SessionRecord(
      sessionId: "authorized",
      autoLabel: "Authorized",
      workspaceDir: "/tmp/authorized",
      cdpPort: 9333,
      socketPath: "/tmp/authorized.sock"
    )
    let blocked = SessionRecord(
      sessionId: "blocked",
      autoLabel: "Blocked",
      workspaceDir: "/tmp/blocked",
      cdpPort: 9444,
      socketPath: "/tmp/blocked.sock"
    )

    appState.authorizeBrowserControl(for: authorized)

    #expect(appState.isSafeMode)
    #expect(appState.isBrowserControlAuthorized(for: authorized))
    #expect(appState.isBrowserControlAuthorized(for: blocked) == false)
    #expect(appState.openCDPInspector(authorized))
    #expect(appState.openCDPInspector(blocked) == false)
    #expect(opener.urls.map(\.absoluteString) == ["http://localhost:9333"])
  }

  @Test("openCDPInspector falls back to port URL when selected target has no id")
  func openCDPInspectorFallsBackToPortURL() async {
    let opener = URLOpenerRecorder()
    let appState = AppState(
      sessionFileProvider: { [] },
      safeModeProvider: { false },
      urlOpener: opener.open
    )
    let session = SessionRecord(
      sessionId: "cdp",
      autoLabel: "CDP",
      workspaceDir: "/tmp/cdp",
      cdpPort: 9333,
      socketPath: "/tmp/cdp.sock",
      pageTargets: [
        CDPPageTarget(
          id: " ",
          type: "page",
          url: "https://example.com",
          title: "Example",
          webSocketDebuggerUrl: "ws://localhost:9333/devtools/page/blank"
        )
      ]
    )

    #expect(appState.openCDPInspector(session))
    #expect(opener.urls.map(\.absoluteString) == ["http://localhost:9333"])
  }

  @Test("external URL opener failure records error")
  func externalURLOpenerFailureRecordsError() async {
    let opener = URLOpenerRecorder(result: false)
    let appState = AppState(
      sessionFileProvider: { [] },
      urlOpener: opener.open
    )
    let session = SessionRecord(
      sessionId: "url",
      autoLabel: "URL",
      workspaceDir: "/tmp/url",
      cdpPort: 9222,
      socketPath: "/tmp/url.sock",
      lastURL: "https://example.com"
    )

    #expect(appState.openCurrentURL(session) == false)
    #expect(appState.lastOpenURLError == "Could not open https://example.com.")

    appState.dismissOpenURLError()

    #expect(appState.lastOpenURLError == nil)
  }

  @Test("refreshTargets preserves valid selected target and saves changed list")
  func refreshTargetsPreservesValidSelection() async {
    let saveCounter = SaveCounter()
    let appState = AppState(
      sessionFileProvider: { [] },
      modelContextSaver: { _ in saveCounter.count += 1 }
    )
    let session = SessionRecord(
      sessionId: "targets",
      autoLabel: "Targets",
      workspaceDir: "/tmp/targets",
      cdpPort: 9222,
      socketPath: "/tmp/targets.sock",
      pageTargets: [
        makePageTarget(id: "first", url: "http://localhost:3000", title: "First"),
        makePageTarget(id: "second", url: "http://localhost:3001", title: "Second"),
      ],
      selectedTargetId: "second"
    )

    let didChange = appState.refreshTargets(
      session,
      pages: [
        makePageInfo(id: "second", url: "http://localhost:3001", title: "Second"),
        makePageInfo(id: "third", url: "http://localhost:3002", title: "Third"),
      ])

    #expect(didChange)
    #expect(saveCounter.count == 1)
    #expect(session.pageTargets.map(\.id) == ["second", "third"])
    #expect(session.selectedTargetId == "second")
  }

  @Test("refreshTargets falls back when selected target disappears")
  func refreshTargetsFallsBackWhenSelectionDisappears() async {
    let appState = AppState(sessionFileProvider: { [] })
    let session = SessionRecord(
      sessionId: "targets",
      autoLabel: "Targets",
      workspaceDir: "/tmp/targets",
      cdpPort: 9222,
      socketPath: "/tmp/targets.sock",
      pageTargets: [
        makePageTarget(id: "second", url: "http://localhost:3001", title: "Second")
      ],
      selectedTargetId: "second"
    )

    appState.refreshTargets(
      session,
      pages: [
        makePageInfo(id: "third", url: "http://localhost:3002", title: "Third")
      ])

    #expect(session.pageTargets.map(\.id) == ["third"])
    #expect(session.selectedTargetId == "third")
  }

  @Test("refreshTargets does not save unchanged list")
  func refreshTargetsDoesNotSaveUnchangedList() async {
    let saveCounter = SaveCounter()
    let appState = AppState(
      sessionFileProvider: { [] },
      modelContextSaver: { _ in saveCounter.count += 1 }
    )
    let session = SessionRecord(
      sessionId: "targets",
      autoLabel: "Targets",
      workspaceDir: "/tmp/targets",
      cdpPort: 9222,
      socketPath: "/tmp/targets.sock",
      pageTargets: [
        makePageTarget(id: "first", url: "http://localhost:3000", title: "First")
      ],
      selectedTargetId: "first"
    )

    let didChange = appState.refreshTargets(
      session,
      pages: [
        makePageInfo(id: "first", url: "http://localhost:3000", title: "First")
      ])

    #expect(!didChange)
    #expect(saveCounter.count == 0)
    #expect(session.selectedTargetId == "first")
  }

  @Test("refreshPlaywrightCLIStatus publishes provider status")
  func refreshPlaywrightCLIStatus() async {
    let appState = AppState(
      sessionFileProvider: { [] },
      cliStatusProvider: PlaywrightCLIStatusProvider { _ in
        ProcessResult(exitStatus: 0, output: "2.0.0\n")
      }
    )

    appState.refreshPlaywrightCLIStatus()
    await waitUntil { appState.playwrightCLIStatus == .available("2.0.0") }

    #expect(appState.playwrightCLIStatus == .available("2.0.0"))
  }

  @Test("diagnostics snapshot includes developer metadata and excludes screenshot data")
  func diagnosticsSnapshotIncludesDeveloperMetadata() async throws {
    let harness = try TestSessionHarness()
    let sessionFile = try harness.writeSession(
      name: "diag-session",
      workspace: harness.workspace("diag-session"),
      port: 9333
    )
    let appState = AppState(
      sessionFileProvider: { [sessionFile] },
      daemonDirectory: harness.root,
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      safeModeProvider: { true }
    )
    appState.setPersistenceDegraded(true, reason: "store locked")
    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    let session = try #require(appState.sessions.first)
    session.lastURL = "https://example.com/private-dev-page"
    session.lastTitle = "Private Dev Page"
    session.lastScreenshot = Data([0x01, 0x02, 0x03])

    let snapshot = appState.makeDiagnosticsSnapshot(now: Date(timeIntervalSince1970: 0))
    let text = snapshot.text

    #expect(snapshot.safeModeEnabled)
    #expect(snapshot.persistenceDegraded)
    #expect(snapshot.persistenceError == "store locked")
    #expect(snapshot.daemonDirectory == harness.root.path)
    #expect(snapshot.sessionFileCount == 1)
    #expect(snapshot.sessionCounts["idle"] == 1)
    #expect(text.contains("sessionId: diag-session"))
    #expect(text.contains("cdpPort: 9333"))
    #expect(text.contains("workspaceDir: \(harness.workspace("diag-session"))"))
    #expect(text.contains("url: https://example.com/private-dev-page"))
    #expect(text.contains("Excludes screenshots, cookies, page content, and recording files."))
    #expect(!text.contains("AQID"))
    #expect(!text.contains("0x01"))
  }

  @Test("feedback summary includes beta support context")
  func feedbackSummaryIncludesBetaSupportContext() async throws {
    let harness = try TestSessionHarness()
    let sessionFile = try harness.writeSession(
      name: "feedback-session",
      workspace: harness.workspace("feedback-session"),
      port: 9334
    )
    let appState = AppState(
      sessionFileProvider: { [sessionFile] },
      daemonDirectory: harness.root,
      shouldStartScreenshots: false,
      syncInterval: .seconds(60),
      cliStatusProvider: PlaywrightCLIStatusProvider { _ in
        ProcessResult(exitStatus: 0, output: "2.0.0\n")
      },
      safeModeProvider: { true }
    )

    appState.startSync(modelContext: harness.context)
    await appState.performSync()
    appState.refreshPlaywrightCLIStatus()
    await waitUntil { appState.playwrightCLIStatus == .available("2.0.0") }

    let text = appState.feedbackSummaryText(now: Date(timeIntervalSince1970: 0))

    #expect(text.contains("Playwright Dashboard Feedback Summary"))
    #expect(text.contains("generatedAt: 1970-01-01T00:00:00.000Z"))
    #expect(text.contains("appVersion:"))
    #expect(text.contains("appBuild:"))
    #expect(text.contains("operatingSystem:"))
    #expect(text.contains("safeModeEnabled: true"))
    #expect(text.contains("playwrightCLIStatus: playwright-cli 2.0.0"))
    #expect(text.contains("openSessionCount: 1"))
    #expect(text.contains("sessionFileCount: 1"))
    #expect(
      text.contains(
        "Please attach a diagnostics export from Settings > Diagnostics > Export Diagnostics."))
  }

  @Test("exportAppDiagnostics writes text and publishes result")
  func exportAppDiagnosticsWritesText() async throws {
    let harness = try TestSessionHarness()
    let exportURL = harness.root.appendingPathComponent("diagnostics.txt")
    let appState = AppState(
      sessionFileProvider: { [] },
      daemonDirectory: harness.root,
      shouldStartScreenshots: false
    )

    #expect(appState.exportAppDiagnostics(to: exportURL))

    let text = try String(contentsOf: exportURL, encoding: .utf8)
    #expect(text.contains("Playwright Dashboard Diagnostics"))
    #expect(text.contains("daemonDirectory: \(harness.root.path)"))
    #expect(appState.lastDiagnosticsExportURL == exportURL)
    #expect(appState.lastDiagnosticsExportError == nil)
  }

  @MainActor
  private final class WatchState {
    var startCount = 0
    var stopCount = 0
  }

  @MainActor
  private final class SaveCounter {
    var count = 0
  }

  private actor CommandRecorder {
    private(set) var commands: [[String]] = []

    func record(_ args: [String]) {
      commands.append(args)
    }
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    let startedAt = ContinuousClock.now
    while !condition(), startedAt.duration(to: .now) < timeout {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @MainActor
  private final class URLOpenerRecorder {
    private let result: Bool
    private(set) var urls: [URL] = []

    init(result: Bool = true) {
      self.result = result
    }

    func open(_ url: URL) -> Bool {
      urls.append(url)
      return result
    }
  }

  private final class SaveFailureSwitch {
    var shouldFail = true
  }

  private enum TestError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
      switch self {
      case .saveFailed:
        return "saveFailed"
      }
    }
  }

  private func makePageInfo(
    id: String,
    type: String = "page",
    url: String,
    title: String
  ) -> CDPClient.PageInfo {
    CDPClient.PageInfo(
      id: id,
      type: type,
      url: url,
      title: title,
      webSocketDebuggerUrl: "ws://localhost/devtools/page/\(id)"
    )
  }

  private func makePageTarget(id: String, url: String, title: String) -> CDPPageTarget {
    CDPPageTarget(
      id: id,
      type: "page",
      url: url,
      title: title,
      webSocketDebuggerUrl: "ws://localhost/devtools/page/\(id)"
    )
  }
}

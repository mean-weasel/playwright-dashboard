import Foundation
import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("SessionManager", .serialized)
struct SessionManagerTests {

  @Test("Creates, updates, closes, and reopens sessions from files")
  func syncLifecycle() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "admin-ux-25c2", workspace: harness.workspace("admin-ux-25c2"), port: 9222)
    ])
    let manager = SessionManager(
      sessionFileProvider: { provider.files }, modelContext: harness.context)

    await manager.syncWithWatcher()

    var sessions = manager.allSessions
    #expect(sessions.count == 1)
    #expect(sessions[0].sessionId == "admin-ux-25c2")
    #expect(sessions[0].autoLabel == "Admin UX")
    #expect(sessions[0].cdpPort == 9222)
    #expect(sessions[0].status == .idle)

    provider.files = [
      try harness.writeSession(
        name: "admin-ux-25c2",
        workspace: harness.workspace("admin-api-9f3a"),
        port: 9444
      )
    ]
    await manager.syncWithWatcher()

    sessions = manager.allSessions
    #expect(sessions[0].workspaceName == "admin-api-9f3a")
    #expect(sessions[0].autoLabel == "Admin API")
    #expect(sessions[0].cdpPort == 9444)

    provider.files = []
    await manager.syncWithWatcher()

    sessions = manager.allSessions
    #expect(sessions[0].status == .closed)
    #expect(sessions[0].userClosed == false)

    provider.files = [
      try harness.writeSession(
        name: "admin-ux-25c2",
        workspace: harness.workspace("admin-api-9f3a"),
        port: 9444
      )
    ]
    await manager.syncWithWatcher()

    sessions = manager.allSessions
    #expect(sessions[0].status == .idle)
    #expect(sessions[0].closedAt == nil)
  }

  @Test("Does not reopen user closed sessions")
  func userClosedSessionStaysClosed() async throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "manual-close", workspace: harness.workspace("manual-close"), port: 9222)
    ])
    let manager = SessionManager(
      sessionFileProvider: { provider.files }, modelContext: harness.context)

    await manager.syncWithWatcher()
    manager.allSessions[0].close(byUser: true)
    try harness.context.save()

    await manager.syncWithWatcher()

    #expect(manager.allSessions[0].status == .closed)
    #expect(manager.allSessions[0].userClosed == true)
  }

  @Test("Purges expired closed sessions whose files are gone")
  func purgesExpiredClosedSessions() async throws {
    let harness = try TestSessionHarness()
    let expired = SessionRecord(
      sessionId: "expired",
      autoLabel: "Expired",
      workspaceDir: harness.workspace("expired"),
      cdpPort: 9222,
      socketPath: "/tmp/expired.sock",
      status: .closed,
      createdAt: Date().addingTimeInterval(-3 * 60 * 60),
      closedAt: Date().addingTimeInterval(-2 * 60 * 60)
    )
    harness.context.insert(expired)
    try harness.context.save()

    let manager = SessionManager(
      sessionFileProvider: { [] },
      modelContext: harness.context,
      closedSessionRetentionProvider: { .seconds(60 * 60) }
    )

    await manager.syncWithWatcher()

    let saved = try harness.context.fetch(FetchDescriptor<SessionRecord>())
    #expect(saved.isEmpty)
    #expect(manager.allSessions.isEmpty)
  }

  @Test("Does not purge closed sessions when retention is disabled")
  func retentionDisabledKeepsClosedSessions() async throws {
    let harness = try TestSessionHarness()
    let closed = SessionRecord(
      sessionId: "closed",
      autoLabel: "Closed",
      workspaceDir: harness.workspace("closed"),
      cdpPort: 9222,
      socketPath: "/tmp/closed.sock",
      status: .closed,
      createdAt: Date().addingTimeInterval(-3 * 60 * 60),
      closedAt: Date().addingTimeInterval(-2 * 60 * 60)
    )
    harness.context.insert(closed)
    try harness.context.save()

    let manager = SessionManager(
      sessionFileProvider: { [] },
      modelContext: harness.context,
      closedSessionRetentionProvider: { nil }
    )

    await manager.syncWithWatcher()

    #expect(manager.allSessions.map(\.sessionId) == ["closed"])
  }

  @Test("Does not purge user closed sessions while their files are live")
  func liveUserClosedSessionIsNotPurged() async throws {
    let harness = try TestSessionHarness()
    let liveFile = try harness.writeSession(
      name: "live-hidden",
      workspace: harness.workspace("live-hidden"),
      port: 9222
    )
    let closed = SessionRecord(
      sessionId: "live-hidden",
      autoLabel: "Live Hidden",
      workspaceDir: harness.workspace("live-hidden"),
      cdpPort: 9222,
      socketPath: "/tmp/live-hidden.sock",
      status: .closed,
      createdAt: Date().addingTimeInterval(-3 * 60 * 60),
      closedAt: Date().addingTimeInterval(-2 * 60 * 60)
    )
    closed.userClosed = true
    harness.context.insert(closed)
    try harness.context.save()

    let manager = SessionManager(
      sessionFileProvider: { [liveFile] },
      modelContext: harness.context,
      closedSessionRetentionProvider: { .seconds(60 * 60) }
    )

    await manager.syncWithWatcher()

    #expect(manager.allSessions.count == 1)
    #expect(manager.allSessions[0].sessionId == "live-hidden")
    #expect(manager.allSessions[0].status == .closed)
    #expect(manager.allSessions[0].userClosed == true)
  }

  @Test("Records malformed session file errors without blocking valid sessions")
  func recordsMalformedSessionFiles() async throws {
    let harness = try TestSessionHarness()
    let validFile = try harness.writeSession(
      name: "valid", workspace: harness.workspace("valid"), port: 9222)
    let malformedFile = harness.root.appendingPathComponent("broken.session")
    try "{ not-json".write(to: malformedFile, atomically: true, encoding: .utf8)

    let manager = SessionManager(
      sessionFileProvider: { [malformedFile, validFile] },
      modelContext: harness.context
    )

    await manager.syncWithWatcher()

    #expect(manager.allSessions.map(\.sessionId) == ["valid"])
    #expect(manager.sessionFileErrors.keys.contains("broken.session"))
  }

  @Test("Clears session file errors after file parses successfully")
  func clearsSessionFileErrorsAfterSuccessfulParse() async throws {
    let harness = try TestSessionHarness()
    let file = harness.root.appendingPathComponent("recover.session")
    try "{ not-json".write(to: file, atomically: true, encoding: .utf8)
    let provider = TestSessionFileProvider(files: [file])
    let manager = SessionManager(
      sessionFileProvider: { provider.files },
      modelContext: harness.context
    )

    await manager.syncWithWatcher()
    #expect(manager.sessionFileErrors.keys.contains("recover.session"))

    provider.files = [
      try harness.writeSession(name: "recover", workspace: harness.workspace("recover"), port: 9222)
    ]
    await manager.syncWithWatcher()

    #expect(manager.sessionFileErrors.isEmpty)
    #expect(manager.allSessions.map(\.sessionId) == ["recover"])
  }
}

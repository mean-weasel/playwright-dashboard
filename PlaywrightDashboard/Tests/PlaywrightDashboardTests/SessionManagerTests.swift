import Foundation
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("SessionManager")
struct SessionManagerTests {

  @Test("Creates, updates, closes, and reopens sessions from files")
  func syncLifecycle() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "admin-ux-25c2", workspace: harness.workspace("admin-ux-25c2"), port: 9222)
    ])
    let manager = SessionManager(
      sessionFileProvider: { provider.files }, modelContext: harness.context)

    manager.syncWithWatcher()

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
    manager.syncWithWatcher()

    sessions = manager.allSessions
    #expect(sessions[0].workspaceName == "admin-api-9f3a")
    #expect(sessions[0].autoLabel == "Admin API")
    #expect(sessions[0].cdpPort == 9444)

    provider.files = []
    manager.syncWithWatcher()

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
    manager.syncWithWatcher()

    sessions = manager.allSessions
    #expect(sessions[0].status == .idle)
    #expect(sessions[0].closedAt == nil)
  }

  @Test("Does not reopen user closed sessions")
  func userClosedSessionStaysClosed() throws {
    let harness = try TestSessionHarness()
    let provider = TestSessionFileProvider(files: [
      try harness.writeSession(
        name: "manual-close", workspace: harness.workspace("manual-close"), port: 9222)
    ])
    let manager = SessionManager(
      sessionFileProvider: { provider.files }, modelContext: harness.context)

    manager.syncWithWatcher()
    manager.allSessions[0].close(byUser: true)
    try harness.context.save()

    manager.syncWithWatcher()

    #expect(manager.allSessions[0].status == .closed)
    #expect(manager.allSessions[0].userClosed == true)
  }
}

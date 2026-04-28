import Testing

@testable import PlaywrightDashboard

// MARK: - displayName

@Suite("SessionRecord.displayName")
struct DisplayNameTests {

  private func makeSession(
    customName: String? = nil, autoLabel: String = "auto-label"
  ) -> SessionRecord {
    SessionRecord(
      sessionId: "test-id",
      autoLabel: autoLabel,
      workspaceDir: "/tmp/test",
      cdpPort: 0,
      socketPath: "/tmp/test.sock",
      customName: customName
    )
  }

  @Test("Returns customName when set")
  func customNameSet() {
    let session = makeSession(customName: "My Session")
    #expect(session.displayName == "My Session")
  }

  @Test("Falls back to autoLabel when customName is nil")
  func customNameNil() {
    let session = makeSession(customName: nil, autoLabel: "Admin UX")
    #expect(session.displayName == "Admin UX")
  }

  @Test("Falls back to autoLabel when customName is explicitly nil")
  func customNameCleared() {
    let session = makeSession(customName: "Old Name")
    session.customName = nil
    #expect(session.displayName == "auto-label")
  }
}

// MARK: - close / reopen

@Suite("SessionRecord.close and reopen")
struct CloseReopenTests {

  private func makeSession(status: SessionStatus = .idle) -> SessionRecord {
    SessionRecord(
      sessionId: "test-id",
      autoLabel: "test",
      workspaceDir: "/tmp/test",
      cdpPort: 9222,
      socketPath: "/tmp/test.sock",
      status: status
    )
  }

  @Test("close() sets status to closed and closedAt")
  func closeBasic() {
    let session = makeSession(status: .active)
    session.close()
    #expect(session.status == .closed)
    #expect(session.closedAt != nil)
    #expect(session.userClosed == false)
  }

  @Test("close(byUser: true) sets userClosed flag")
  func closeByUser() {
    let session = makeSession(status: .active)
    session.close(byUser: true)
    #expect(session.status == .closed)
    #expect(session.closedAt != nil)
    #expect(session.userClosed == true)
  }

  @Test("close(byUser: false) does not set userClosed flag")
  func closeBySync() {
    let session = makeSession(status: .idle)
    session.close(byUser: false)
    #expect(session.status == .closed)
    #expect(session.userClosed == false)
  }

  @Test("reopen() resets status, closedAt, and userClosed")
  func reopenBasic() {
    let session = makeSession(status: .active)
    session.close(byUser: true)
    session.reopen()
    #expect(session.status == .idle)
    #expect(session.closedAt == nil)
    #expect(session.userClosed == false)
  }

  @Test("reopen() clears userClosed even if it was set")
  func reopenClearsUserClosed() {
    let session = makeSession()
    session.userClosed = true
    session.status = .closed
    session.reopen()
    #expect(session.userClosed == false)
  }
}

// MARK: - SidebarFilter matching

@Suite("SidebarFilter filtering logic")
struct SidebarFilterTests {

  private func makeSessions() -> [SessionRecord] {
    let active = SessionRecord(
      sessionId: "active-1", autoLabel: "Active", workspaceDir: "/tmp/app-a",
      cdpPort: 9222, socketPath: "/tmp/a.sock", status: .active)
    let idle = SessionRecord(
      sessionId: "idle-1", autoLabel: "Idle", workspaceDir: "/tmp/app-a",
      cdpPort: 9223, socketPath: "/tmp/b.sock", status: .idle)
    let stale = SessionRecord(
      sessionId: "stale-1", autoLabel: "Stale", workspaceDir: "/tmp/app-b",
      cdpPort: 9224, socketPath: "/tmp/c.sock", status: .stale)
    let closed = SessionRecord(
      sessionId: "closed-1", autoLabel: "Closed", workspaceDir: "/tmp/app-a",
      cdpPort: 9225, socketPath: "/tmp/d.sock", status: .closed)
    return [active, idle, stale, closed]
  }

  private func filter(
    _ sessions: [SessionRecord], by sidebarFilter: SidebarFilter?
  ) -> [SessionRecord] {
    var result = sessions
    switch sidebarFilter {
    case .allOpen:
      result = result.filter { $0.status != .closed }
    case .idleStale:
      result = result.filter { $0.status == .idle || $0.status == .stale }
    case .closed:
      result = result.filter { $0.status == .closed }
    case .workspace(let name):
      result = result.filter { $0.projectName == name && $0.status != .closed }
    case nil:
      result = result.filter { $0.status != .closed }
    }
    return result
  }

  @Test("allOpen excludes closed sessions")
  func allOpen() {
    let sessions = makeSessions()
    let filtered = filter(sessions, by: .allOpen)
    #expect(filtered.count == 3)
    #expect(filtered.allSatisfy { $0.status != .closed })
  }

  @Test("idleStale returns only idle and stale")
  func idleStale() {
    let sessions = makeSessions()
    let filtered = filter(sessions, by: .idleStale)
    #expect(filtered.count == 2)
    #expect(filtered.allSatisfy { $0.status == .idle || $0.status == .stale })
  }

  @Test("closed returns only closed sessions")
  func closed() {
    let sessions = makeSessions()
    let filtered = filter(sessions, by: .closed)
    #expect(filtered.count == 1)
    #expect(filtered[0].sessionId == "closed-1")
  }

  @Test("nil filter excludes closed (same as allOpen)")
  func nilFilter() {
    let sessions = makeSessions()
    let filtered = filter(sessions, by: nil)
    #expect(filtered.count == 3)
    #expect(filtered.allSatisfy { $0.status != .closed })
  }

  @Test("workspace filter returns matching project, excludes closed")
  func workspaceFilter() {
    let sessions = makeSessions()
    // app-a has: active, idle, closed — filter should return active + idle only
    let filtered = filter(sessions, by: .workspace("app-a"))
    #expect(filtered.count == 2)
    #expect(filtered.allSatisfy { $0.projectName == "app-a" && $0.status != .closed })
  }
}

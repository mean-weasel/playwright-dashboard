import Testing

@testable import PlaywrightDashboard

@Suite("SessionTerminator")
struct SessionTerminatorTests {

  @Test("close invokes playwright-cli close for the session")
  func closeBuildsCommand() async throws {
    let recorder = CommandRecorder()
    let terminator = SessionTerminator { args in
      await recorder.record(args)
      return ProcessResult(exitStatus: 0, output: "")
    }

    try await terminator.close(sessionId: "admin-ux")

    #expect(await recorder.commands == [["-s=admin-ux", "close"]])
  }

  @Test("close throws when playwright-cli fails")
  func closeThrowsOnFailure() async throws {
    let terminator = SessionTerminator { _ in
      ProcessResult(exitStatus: 2, output: "missing session")
    }

    do {
      try await terminator.close(sessionId: "missing")
      Issue.record("Expected close to throw")
    } catch let error as SessionTerminationError {
      #expect(error == .commandFailed(2, "missing session"))
    }
  }

  private actor CommandRecorder {
    private(set) var commands: [[String]] = []

    func record(_ args: [String]) {
      commands.append(args)
    }
  }
}

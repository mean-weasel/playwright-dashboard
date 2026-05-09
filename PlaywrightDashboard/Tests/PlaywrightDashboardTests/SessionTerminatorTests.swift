import Foundation
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

  @Test("process output is read while running and truncated")
  func processOutputIsReadWhileRunningAndTruncated() async throws {
    let script = """
      i=0
      while [ $i -lt 5000 ]; do
        printf '0123456789abcdef0123456789abcdef\\n'
        i=$((i + 1))
      done
      exit 7
      """

    let result = try await SessionTerminator.runProcess(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", script],
      timeout: 2,
      outputLimit: 1_024
    )

    #expect(result.exitStatus == 7)
    #expect(result.output.contains("0123456789abcdef"))
    #expect(result.output.contains("[output truncated after 1024 bytes]"))
  }

  @Test("process is terminated on timeout and reports captured output")
  func processTerminatesOnTimeout() async throws {
    let script = """
      printf 'started close\\n'
      sleep 5
      """

    do {
      _ = try await SessionTerminator.runProcess(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", script],
        timeout: 0.1,
        outputLimit: 1_024
      )
      Issue.record("Expected process timeout")
    } catch let error as SessionTerminationError {
      guard case .commandTimedOut(let timeout, let output) = error else {
        Issue.record("Expected timeout error, got \(error)")
        return
      }
      #expect(timeout == 0.1)
      #expect(output.contains("started close"))
      #expect(error.errorDescription?.contains("playwright-cli close timed out") == true)
    }
  }

  private actor CommandRecorder {
    private(set) var commands: [[String]] = []

    func record(_ args: [String]) {
      commands.append(args)
    }
  }
}

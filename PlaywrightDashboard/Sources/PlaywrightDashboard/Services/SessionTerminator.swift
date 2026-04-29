import Foundation
import OSLog

private let sessionTerminatorLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "SessionTerminator")

enum SessionTerminationError: Error, LocalizedError, Equatable {
  case executableNotFound
  case commandFailed(Int32, String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      "playwright-cli was not found on PATH"
    case .commandFailed(let status, let output):
      "playwright-cli close failed with status \(status): \(output)"
    }
  }
}

struct ProcessResult: Sendable {
  let exitStatus: Int32
  let output: String
}

struct SessionTerminator: Sendable {
  typealias Runner = @Sendable ([String]) async throws -> ProcessResult

  private let runner: Runner

  init(runner: @escaping Runner = SessionTerminator.runPlaywrightCLI) {
    self.runner = runner
  }

  func close(sessionId: String) async throws {
    let args = ["-s=\(sessionId)", "close"]
    let result = try await runner(args)
    guard result.exitStatus == 0 else {
      throw SessionTerminationError.commandFailed(result.exitStatus, result.output)
    }
  }

  static func runPlaywrightCLI(args: [String]) async throws -> ProcessResult {
    try await Task.detached(priority: .utility) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["playwright-cli"] + args

      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe

      do {
        try process.run()
      } catch {
        sessionTerminatorLogger.warning(
          "Failed to launch playwright-cli: \(error.localizedDescription)")
        throw SessionTerminationError.executableNotFound
      }

      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      return ProcessResult(exitStatus: process.terminationStatus, output: output)
    }.value
  }
}

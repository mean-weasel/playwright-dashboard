import Foundation
import OSLog

private let sessionTerminatorLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "SessionTerminator")

enum SessionTerminationError: Error, LocalizedError, Equatable {
  case executableNotFound
  case commandFailed(Int32, String)
  case commandTimedOut(TimeInterval, String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      "playwright-cli was not found on PATH"
    case .commandFailed(let status, let output):
      "playwright-cli close failed with status \(status): \(output)"
    case .commandTimedOut(let timeout, let output):
      "playwright-cli close timed out after \(Self.format(timeout)) seconds: \(output)"
    }
  }

  private static func format(_ seconds: TimeInterval) -> String {
    let rounded = seconds.rounded()
    if seconds == rounded {
      return String(Int(rounded))
    }
    return String(format: "%.1f", seconds)
  }
}

struct ProcessResult: Sendable {
  let exitStatus: Int32
  let output: String
}

struct SessionTerminator: Sendable {
  typealias Runner = @Sendable ([String]) async throws -> ProcessResult

  static let defaultCloseTimeout: TimeInterval = 10
  static let defaultOutputLimit = 8 * 1024

  private let runner: Runner

  init(
    runner: @escaping Runner = { args in try await SessionTerminator.runPlaywrightCLI(args: args) }
  ) {
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
    try await runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: ["playwright-cli"] + args,
      timeout: defaultCloseTimeout,
      outputLimit: defaultOutputLimit
    )
  }

  static func runProcess(
    executableURL: URL,
    arguments: [String],
    timeout: TimeInterval = defaultCloseTimeout,
    outputLimit: Int = defaultOutputLimit
  ) async throws -> ProcessResult {
    try await Task.detached(priority: .utility) { @Sendable in
      try runProcessSynchronously(
        executableURL: executableURL,
        arguments: arguments,
        timeout: timeout,
        outputLimit: outputLimit
      )
    }.value
  }

  private static func runProcessSynchronously(
    executableURL: URL,
    arguments: [String],
    timeout: TimeInterval,
    outputLimit: Int
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let output = ProcessOutputBuffer(limit: outputLimit)
    let readHandle = pipe.fileHandleForReading
    readHandle.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        output.append(data)
      }
    }

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      exited.signal()
    }

    do {
      try process.run()
    } catch {
      readHandle.readabilityHandler = nil
      sessionTerminatorLogger.warning(
        "Failed to launch playwright-cli: \(error.localizedDescription)")
      throw SessionTerminationError.executableNotFound
    }

    let timedOut = exited.wait(timeout: deadline(after: timeout)) == .timedOut
    if timedOut {
      process.terminate()
      if exited.wait(timeout: deadline(after: 2)) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }

    readHandle.readabilityHandler = nil
    output.append(readHandle.readDataToEndOfFile())

    let capturedOutput = output.string()
    if timedOut {
      throw SessionTerminationError.commandTimedOut(timeout, capturedOutput)
    }
    return ProcessResult(exitStatus: process.terminationStatus, output: capturedOutput)
  }
}

private func deadline(after seconds: TimeInterval) -> DispatchTime {
  .now() + .milliseconds(max(0, Int((seconds * 1_000).rounded(.up))))
}

private final class ProcessOutputBuffer: @unchecked Sendable {
  private let limit: Int
  private let lock = NSLock()
  private var data = Data()
  private var totalBytes = 0

  init(limit: Int) {
    self.limit = max(0, limit)
  }

  func append(_ newData: Data) {
    guard !newData.isEmpty else { return }

    lock.lock()
    defer { lock.unlock() }

    totalBytes += newData.count
    guard data.count < limit else { return }

    let remaining = limit - data.count
    if newData.count <= remaining {
      data.append(newData)
    } else {
      data.append(newData.prefix(remaining))
    }
  }

  func string() -> String {
    lock.lock()
    defer { lock.unlock() }

    var result = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    if totalBytes > limit {
      if !result.isEmpty, !result.hasSuffix("\n") {
        result += "\n"
      }
      result += "[output truncated after \(limit) bytes]"
    }
    return result
  }
}

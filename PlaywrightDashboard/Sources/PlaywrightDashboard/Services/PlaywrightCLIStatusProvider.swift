import Foundation

enum PlaywrightCLIStatus: Equatable, Sendable {
  case unknown
  case available(String?)
  case unavailable

  var isAvailable: Bool {
    if case .available = self { true } else { false }
  }

  var displayText: String {
    switch self {
    case .unknown:
      "Checking playwright-cli..."
    case .available(let version):
      version.map { "playwright-cli \($0)" } ?? "playwright-cli available"
    case .unavailable:
      "playwright-cli not found"
    }
  }
}

struct PlaywrightCLIStatusProvider: Sendable {
  typealias Runner = @Sendable ([String]) async throws -> ProcessResult

  private let runner: Runner

  init(runner: @escaping Runner = SessionTerminator.runPlaywrightCLI) {
    self.runner = runner
  }

  func status() async -> PlaywrightCLIStatus {
    do {
      let result = try await runner(["--version"])
      guard result.exitStatus == 0 else { return .unavailable }
      let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      return .available(version.isEmpty ? nil : version)
    } catch {
      return .unavailable
    }
  }
}

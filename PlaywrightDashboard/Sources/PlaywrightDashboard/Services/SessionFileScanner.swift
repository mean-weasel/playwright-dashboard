import Foundation
import OSLog

private let sessionFileScannerLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "SessionFileScanner")

struct SessionFileScanResult: Sendable {
  let configs: [SessionFileConfig]
  let errors: [String: String]
}

actor SessionFileScanner {
  private let decoder = JSONDecoder()

  func scan(_ fileURLs: [URL]) -> SessionFileScanResult {
    var configs: [SessionFileConfig] = []
    var errors: [String: String] = [:]

    for url in fileURLs {
      do {
        let data = try Data(contentsOf: url)
        configs.append(try decoder.decode(SessionFileConfig.self, from: data))
      } catch {
        sessionFileScannerLogger.debug(
          "Cannot read or parse session file \(url.lastPathComponent): \(error.localizedDescription)"
        )
        errors[url.lastPathComponent] = error.localizedDescription
      }
    }

    return SessionFileScanResult(configs: configs, errors: errors)
  }
}

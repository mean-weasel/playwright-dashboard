import Foundation
import OSLog

private let sessionFileScannerLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "SessionFileScanner")

struct SessionFileScanResult: Sendable {
  let configs: [SessionFileConfig]
  let errors: [String: String]
  let skippedFiles: [String: String]
}

actor SessionFileScanner {
  static let defaultMaxSessionFileBytes = 512 * 1024
  static let defaultMaxFilesPerScan = 100

  private let decoder = JSONDecoder()
  private let maxSessionFileBytes: Int
  private let maxFilesPerScan: Int

  init(
    maxSessionFileBytes: Int = SessionFileScanner.defaultMaxSessionFileBytes,
    maxFilesPerScan: Int = SessionFileScanner.defaultMaxFilesPerScan
  ) {
    self.maxSessionFileBytes = max(0, maxSessionFileBytes)
    self.maxFilesPerScan = max(0, maxFilesPerScan)
  }

  func scan(_ fileURLs: [URL]) -> SessionFileScanResult {
    var configs: [SessionFileConfig] = []
    var errors: [String: String] = [:]
    var skippedFiles: [String: String] = [:]

    for url in fileURLs.prefix(maxFilesPerScan) {
      do {
        if let fileSize = try sessionFileSize(url), fileSize > maxSessionFileBytes {
          let message =
            "Skipped session file: file size \(fileSize) bytes exceeds limit of \(maxSessionFileBytes) bytes"
          sessionFileScannerLogger.debug(
            "Skipping session file \(url.lastPathComponent): \(message)"
          )
          errors[url.lastPathComponent] = message
          skippedFiles[url.lastPathComponent] = message
          continue
        }

        let data = try Data(contentsOf: url)
        configs.append(try decoder.decode(SessionFileConfig.self, from: data))
      } catch {
        sessionFileScannerLogger.debug(
          "Cannot read or parse session file \(url.lastPathComponent): \(error.localizedDescription)"
        )
        errors[url.lastPathComponent] = error.localizedDescription
      }
    }

    if fileURLs.count > maxFilesPerScan {
      for url in fileURLs.dropFirst(maxFilesPerScan) {
        let message =
          "Skipped session file: scan limit of \(maxFilesPerScan) files reached"
        sessionFileScannerLogger.debug(
          "Skipping session file \(url.lastPathComponent): \(message)"
        )
        errors[url.lastPathComponent] = message
        skippedFiles[url.lastPathComponent] = message
      }
    }

    return SessionFileScanResult(configs: configs, errors: errors, skippedFiles: skippedFiles)
  }

  private func sessionFileSize(_ url: URL) throws -> Int? {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return values.fileSize
  }
}

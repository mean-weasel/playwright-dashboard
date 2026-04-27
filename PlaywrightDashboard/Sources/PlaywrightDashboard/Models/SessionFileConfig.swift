import Foundation

/// Decoded representation of a Playwright `.session` JSON file on disk.
struct SessionFileConfig: Codable {
  let name: String
  let version: String
  let timestamp: Int
  let socketPath: String
  let workspaceDir: String
  let cli: CLIConfig
  let browser: BrowserConfig

  // MARK: - Nested types

  struct CLIConfig: Codable {}

  struct BrowserConfig: Codable {
    let browserName: String
    let launchOptions: LaunchOptions

    struct LaunchOptions: Codable {
      let headless: Bool?
      let chromiumSandbox: Bool?
      let args: [String]
    }
  }

  // MARK: - Computed

  /// Extracts the remote debugging port from `--remote-debugging-port=XXXXX` in launch args.
  var cdpPort: Int? {
    let prefix = "--remote-debugging-port="
    for arg in browser.launchOptions.args {
      if arg.hasPrefix(prefix) {
        let portString = String(arg.dropFirst(prefix.count))
        return Int(portString)
      }
    }
    return nil
  }
}

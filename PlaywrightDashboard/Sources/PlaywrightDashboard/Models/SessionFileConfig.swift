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
      let cdpPort: Int?
      let args: [String]

      init(
        headless: Bool?,
        chromiumSandbox: Bool?,
        cdpPort: Int? = nil,
        args: [String] = []
      ) {
        self.headless = headless
        self.chromiumSandbox = chromiumSandbox
        self.cdpPort = cdpPort
        self.args = args
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headless = try container.decodeIfPresent(Bool.self, forKey: .headless)
        chromiumSandbox = try container.decodeIfPresent(Bool.self, forKey: .chromiumSandbox)
        cdpPort = try container.decodeIfPresent(Int.self, forKey: .cdpPort)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
      }
    }
  }

  // MARK: - Computed

  init(
    name: String,
    version: String,
    timestamp: Int,
    socketPath: String,
    workspaceDir: String = "",
    cli: CLIConfig,
    browser: BrowserConfig
  ) {
    self.name = name
    self.version = version
    self.timestamp = timestamp
    self.socketPath = socketPath
    self.workspaceDir = workspaceDir
    self.cli = cli
    self.browser = browser
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    version = try container.decode(String.self, forKey: .version)
    timestamp = try container.decode(Int.self, forKey: .timestamp)
    socketPath = try container.decode(String.self, forKey: .socketPath)
    workspaceDir = try container.decodeIfPresent(String.self, forKey: .workspaceDir) ?? ""
    cli = try container.decode(CLIConfig.self, forKey: .cli)
    browser = try container.decode(BrowserConfig.self, forKey: .browser)
  }

  /// Extracts the remote debugging port from modern `cdpPort` or legacy launch args.
  var cdpPort: Int? {
    if let directPort = browser.launchOptions.cdpPort {
      return directPort
    }

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

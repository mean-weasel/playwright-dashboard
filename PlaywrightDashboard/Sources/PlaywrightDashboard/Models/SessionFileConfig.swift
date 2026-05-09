import Foundation

/// Decoded representation of a Playwright `.session` JSON file on disk.
struct SessionFileConfig: Codable, Sendable {
  static let maximumStringFieldLength = 4096

  let name: String
  let version: String
  let timestamp: Int
  let socketPath: String
  let workspaceDir: String
  let cli: CLIConfig
  let browser: BrowserConfig

  // MARK: - Nested types

  struct CLIConfig: Codable, Sendable {}

  struct BrowserConfig: Codable, Sendable {
    let browserName: String
    let launchOptions: LaunchOptions

    init(browserName: String, launchOptions: LaunchOptions) {
      self.browserName = browserName
      self.launchOptions = launchOptions
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      browserName = try container.decodeBoundedString(forKey: .browserName)
      launchOptions = try container.decode(LaunchOptions.self, forKey: .launchOptions)
    }

    struct LaunchOptions: Codable, Sendable {
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
        if let decodedPort = try container.decodeIfPresent(Int.self, forKey: .cdpPort) {
          guard (1...65_535).contains(decodedPort) else {
            throw DecodingError.dataCorruptedError(
              forKey: .cdpPort,
              in: container,
              debugDescription: "cdpPort must be between 1 and 65535"
            )
          }
          cdpPort = decodedPort
        } else {
          cdpPort = nil
        }
        args = try container.decodeStringArrayIfPresent(forKey: .args) ?? []
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
    name = try container.decodeBoundedString(forKey: .name)
    version = try container.decodeBoundedString(forKey: .version)
    timestamp = try container.decode(Int.self, forKey: .timestamp)
    socketPath = try container.decodeBoundedString(forKey: .socketPath)
    workspaceDir = try container.decodeBoundedStringIfPresent(forKey: .workspaceDir) ?? ""
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
        guard let port = Int(portString), (1...65_535).contains(port) else {
          return nil
        }
        return port
      }
    }
    return nil
  }
}

extension KeyedDecodingContainer {
  fileprivate func decodeBoundedString(forKey key: Key) throws -> String {
    let value = try decode(String.self, forKey: key)
    try validateStringLength(value, forKey: key)
    return value
  }

  fileprivate func decodeBoundedStringIfPresent(forKey key: Key) throws -> String? {
    guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
    try validateStringLength(value, forKey: key)
    return value
  }

  fileprivate func decodeStringArrayIfPresent(forKey key: Key) throws -> [String]? {
    guard let values = try decodeIfPresent([String].self, forKey: key) else { return nil }
    for value in values {
      try validateStringLength(value, forKey: key)
    }
    return values
  }

  fileprivate func validateStringLength(_ value: String, forKey key: Key) throws {
    guard value.count <= SessionFileConfig.maximumStringFieldLength else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: self,
        debugDescription:
          "\(key.stringValue) exceeds maximum length of \(SessionFileConfig.maximumStringFieldLength)"
      )
    }
  }
}

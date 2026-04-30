#!/usr/bin/env swift

import Foundation

struct SessionFileConfig: Decodable {
  struct BrowserConfig: Decodable {
    struct LaunchOptions: Decodable {
      let args: [String]
      let cdpPort: Int?

      enum CodingKeys: String, CodingKey {
        case args
        case cdpPort
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        cdpPort = try container.decodeIfPresent(Int.self, forKey: .cdpPort)
      }
    }

    let launchOptions: LaunchOptions
  }

  let browser: BrowserConfig

  var cdpPort: Int? {
    if let cdpPort = browser.launchOptions.cdpPort {
      return cdpPort
    }

    let prefix = "--remote-debugging-port="
    for arg in browser.launchOptions.args where arg.hasPrefix(prefix) {
      return Int(arg.dropFirst(prefix.count))
    }
    return nil
  }
}

let daemonDirectory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Caches/ms-playwright/daemon", isDirectory: true)

guard let enumerator = FileManager.default.enumerator(
  at: daemonDirectory,
  includingPropertiesForKeys: [.isRegularFileKey],
  options: [.skipsHiddenFiles]
) else {
  exit(1)
}

for case let url as URL in enumerator where url.pathExtension == "session" {
  guard let data = try? Data(contentsOf: url),
    let config = try? JSONDecoder().decode(SessionFileConfig.self, from: data),
    let port = config.cdpPort
  else {
    continue
  }

  print(port)
  exit(0)
}

exit(1)

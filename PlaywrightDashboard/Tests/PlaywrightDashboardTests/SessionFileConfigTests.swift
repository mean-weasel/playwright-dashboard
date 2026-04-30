import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("SessionFileConfig.cdpPort")
struct SessionFileConfigTests {

  private func makeConfig(args: [String]) -> SessionFileConfig {
    SessionFileConfig(
      name: "test-session",
      version: "1.0",
      timestamp: 0,
      socketPath: "/tmp/test.sock",
      workspaceDir: "/tmp/workspace",
      cli: .init(),
      browser: .init(
        browserName: "chromium",
        launchOptions: .init(headless: true, chromiumSandbox: false, args: args)
      )
    )
  }

  private func decode(_ json: String) throws -> SessionFileConfig {
    try JSONDecoder().decode(SessionFileConfig.self, from: Data(json.utf8))
  }

  @Test("Extracts port from standard arg")
  func standardPort() {
    let config = makeConfig(args: ["--remote-debugging-port=9222"])
    #expect(config.cdpPort == 9222)
  }

  @Test("Returns nil when port arg is absent")
  func noPortArg() {
    let config = makeConfig(args: ["--headless", "--no-sandbox"])
    #expect(config.cdpPort == nil)
  }

  @Test("Returns nil for empty args")
  func emptyArgs() {
    let config = makeConfig(args: [])
    #expect(config.cdpPort == nil)
  }

  @Test("Finds port among multiple args")
  func portAmongOthers() {
    let config = makeConfig(args: [
      "--headless",
      "--remote-debugging-port=44519",
      "--disable-gpu",
    ])
    #expect(config.cdpPort == 44519)
  }

  @Test("Returns nil for malformed port value")
  func malformedPort() {
    let config = makeConfig(args: ["--remote-debugging-port=abc"])
    #expect(config.cdpPort == nil)
  }

  @Test("Uses direct cdpPort from current playwright-cli session files")
  func directCDPPort() throws {
    let config = try decode(
      """
      {
        "name": "pdsmoke",
        "version": "1.60.0-alpha",
        "timestamp": 1777565773957,
        "socketPath": "/tmp/pw/session.sock",
        "cli": {},
        "browser": {
          "browserName": "chromium",
          "launchOptions": {
            "assistantMode": true,
            "headless": true,
            "channel": "chrome",
            "cdpPort": 51546
          }
        }
      }
      """)

    #expect(config.workspaceDir == "")
    #expect(config.browser.launchOptions.args == [])
    #expect(config.cdpPort == 51546)
  }

  @Test("Direct cdpPort takes precedence over legacy launch arg")
  func directPortPrecedence() {
    let config = SessionFileConfig(
      name: "test-session",
      version: "1.0",
      timestamp: 0,
      socketPath: "/tmp/test.sock",
      workspaceDir: "/tmp/workspace",
      cli: .init(),
      browser: .init(
        browserName: "chromium",
        launchOptions: .init(
          headless: true,
          chromiumSandbox: false,
          cdpPort: 51546,
          args: ["--remote-debugging-port=9222"]
        )
      )
    )

    #expect(config.cdpPort == 51546)
  }
}

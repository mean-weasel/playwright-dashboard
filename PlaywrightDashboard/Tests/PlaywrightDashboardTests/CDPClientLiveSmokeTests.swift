import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("CDPClient live smoke")
struct CDPClientLiveSmokeTests {

  @Test("captures a screenshot from a live CDP endpoint")
  func liveScreenshotCapture() async throws {
    guard let port = try liveCDPPort() else { return }
    let client = CDPClient(port: port, requestTimeout: .seconds(5))
    let result = try await client.captureScreenshot(quality: 20)

    #expect(result.jpeg.count > 0)
  }

  @Test("forwards pointer input to a live CDP endpoint")
  func livePointerForwarding() async throws {
    guard ProcessInfo.processInfo.environment["RUN_LIVE_CDP_INTERACTION_SMOKE"] == "1" else {
      return
    }
    guard let port = try liveCDPPort() else { return }
    let client = CDPClient(port: port, requestTimeout: .seconds(5))

    try await client.dispatchMouseClick(x: 10, y: 10)
    try await client.dispatchMouseWheel(x: 10, y: 10, deltaX: 0, deltaY: -20)
  }

  private func liveCDPPort() throws -> Int? {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_LIVE_CDP_SMOKE"] == "1" else { return nil }
    let portString = try #require(environment["LIVE_CDP_PORT"])
    guard let port = Int(portString) else {
      throw LiveCDPConfigurationError.invalidPort(portString)
    }
    return port
  }

  private enum LiveCDPConfigurationError: Error {
    case invalidPort(String)
  }
}

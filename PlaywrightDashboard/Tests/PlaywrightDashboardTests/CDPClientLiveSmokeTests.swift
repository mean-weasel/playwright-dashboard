import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("CDPClient live smoke")
struct CDPClientLiveSmokeTests {

  @Test("captures a screenshot from a live CDP endpoint")
  func liveScreenshotCapture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_LIVE_CDP_SMOKE"] == "1" else { return }
    let portString = try #require(environment["LIVE_CDP_PORT"])
    let port = try #require(Int(portString))

    let client = CDPClient(port: port, requestTimeout: .seconds(5))
    let result = try await client.captureScreenshot(quality: 20)

    #expect(result.jpeg.count > 0)
  }
}

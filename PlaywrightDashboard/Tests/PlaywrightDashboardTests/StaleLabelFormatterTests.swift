import Testing

@testable import PlaywrightDashboard

@Suite("StaleLabelFormatter")
struct StaleLabelFormatterTests {

  @Test("Uses no navigation for nil URL")
  func nilURL() {
    #expect(StaleLabelFormatter.reason(lastURL: nil, thresholdSeconds: 300) == "No navigation")
  }

  @Test("Uses no navigation for about blank")
  func aboutBlank() {
    #expect(
      StaleLabelFormatter.reason(lastURL: "about:blank", thresholdSeconds: 300)
        == "No navigation")
  }

  @Test("Formats minute thresholds")
  func minuteThresholds() {
    #expect(
      StaleLabelFormatter.reason(lastURL: "https://example.com", thresholdSeconds: 60)
        == "Idle 1m+")
    #expect(
      StaleLabelFormatter.reason(lastURL: "https://example.com", thresholdSeconds: 600)
        == "Idle 10m+")
  }

  @Test("Formats never threshold generically")
  func neverThreshold() {
    #expect(
      StaleLabelFormatter.reason(lastURL: "https://example.com", thresholdSeconds: 0)
        == "Idle")
  }
}

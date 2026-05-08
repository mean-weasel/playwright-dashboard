import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("DashboardSettings")
struct DashboardSettingsTests {

  @Test("quality values are clamped")
  func qualityClamping() {
    #expect(DashboardSettings.clampedQuality(-10) == 1)
    #expect(DashboardSettings.clampedQuality(50) == 50)
    #expect(DashboardSettings.clampedQuality(250) == 100)
  }

  @Test("refresh durations use minimums")
  func refreshDurationMinimums() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!
    defaults.set(0, forKey: DashboardSettings.thumbnailRefreshSecondsKey)
    defaults.set(100, forKey: DashboardSettings.expandedRefreshMillisecondsKey)

    #expect(DashboardSettings.thumbnailRefreshDuration(defaults: defaults) == .seconds(1))
    #expect(DashboardSettings.expandedRefreshDuration(defaults: defaults) == .milliseconds(500))
  }

  @Test("stored quality values are clamped")
  func storedQualityClamping() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!
    defaults.set(0, forKey: DashboardSettings.thumbnailQualityKey)
    defaults.set(250, forKey: DashboardSettings.expandedQualityKey)

    #expect(DashboardSettings.thumbnailQuality(defaults: defaults) == 1)
    #expect(DashboardSettings.expandedQuality(defaults: defaults) == 100)
  }

  @Test("closed session retention supports durations and never")
  func closedSessionRetention() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!

    defaults.set(24, forKey: DashboardSettings.closedSessionRetentionHoursKey)
    #expect(DashboardSettings.closedSessionRetention(defaults: defaults) == .seconds(24 * 60 * 60))

    defaults.set(0, forKey: DashboardSettings.closedSessionRetentionHoursKey)
    #expect(DashboardSettings.closedSessionRetention(defaults: defaults) == nil)
  }

  @Test("forced expanded snapshot fallback defaults off and can be enabled")
  func forceExpandedSnapshotFallback() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!

    #expect(DashboardSettings.forceExpandedSnapshotFallback(defaults: defaults) == false)

    defaults.set(true, forKey: DashboardSettings.forceExpandedSnapshotFallbackKey)
    #expect(DashboardSettings.forceExpandedSnapshotFallback(defaults: defaults))
  }

  @Test("safe mode defaults on and can be disabled")
  func safeMode() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!
    defaults.register(defaults: DashboardSettings.registrationDefaults())

    #expect(DashboardSettings.safeMode(defaults: defaults))

    defaults.set(false, forKey: DashboardSettings.safeModeKey)
    #expect(DashboardSettings.safeMode(defaults: defaults) == false)
  }

  @Test("safe mode onboarding defaults visible and can be dismissed")
  func safeModeOnboardingDismissal() {
    let defaults = UserDefaults(suiteName: "DashboardSettingsTests-\(UUID().uuidString)")!
    defaults.register(defaults: DashboardSettings.registrationDefaults())

    #expect(DashboardSettings.safeModeOnboardingDismissed(defaults: defaults) == false)

    defaults.set(true, forKey: DashboardSettings.safeModeOnboardingDismissedKey)
    #expect(DashboardSettings.safeModeOnboardingDismissed(defaults: defaults))
  }
}

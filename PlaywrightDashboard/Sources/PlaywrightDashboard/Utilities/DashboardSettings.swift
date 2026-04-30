import Foundation

enum DashboardSettings {
  static let staleThresholdSecondsKey = "staleThresholdSeconds"
  static let thumbnailRefreshSecondsKey = "thumbnailRefreshSeconds"
  static let thumbnailQualityKey = "thumbnailQuality"
  static let expandedRefreshMillisecondsKey = "expandedRefreshMilliseconds"
  static let expandedQualityKey = "expandedQuality"
  static let closedSessionRetentionHoursKey = "closedSessionRetentionHours"
  static let forceExpandedSnapshotFallbackKey = "forceExpandedSnapshotFallback"

  static func registrationDefaults() -> [String: Any] {
    [
      staleThresholdSecondsKey: 120,
      thumbnailRefreshSecondsKey: 5,
      thumbnailQualityKey: 50,
      expandedRefreshMillisecondsKey: 1500,
      expandedQualityKey: 60,
      closedSessionRetentionHoursKey: 24,
      forceExpandedSnapshotFallbackKey: false,
    ]
  }

  static func clampedQuality(_ quality: Int) -> Int {
    min(100, max(1, quality))
  }

  static func thumbnailRefreshDuration(defaults: UserDefaults = .standard) -> Duration {
    let seconds = max(1, defaults.integer(forKey: thumbnailRefreshSecondsKey))
    return .seconds(seconds)
  }

  static func thumbnailQuality(defaults: UserDefaults = .standard) -> Int {
    clampedQuality(defaults.integer(forKey: thumbnailQualityKey))
  }

  static func expandedRefreshDuration(defaults: UserDefaults = .standard) -> Duration {
    let milliseconds = max(500, defaults.integer(forKey: expandedRefreshMillisecondsKey))
    return .milliseconds(milliseconds)
  }

  static func expandedQuality(defaults: UserDefaults = .standard) -> Int {
    clampedQuality(defaults.integer(forKey: expandedQualityKey))
  }

  static func closedSessionRetention(defaults: UserDefaults = .standard) -> Duration? {
    let hours = defaults.integer(forKey: closedSessionRetentionHoursKey)
    guard hours > 0 else { return nil }
    return .seconds(hours * 60 * 60)
  }

  static func forceExpandedSnapshotFallback(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: forceExpandedSnapshotFallbackKey)
  }
}

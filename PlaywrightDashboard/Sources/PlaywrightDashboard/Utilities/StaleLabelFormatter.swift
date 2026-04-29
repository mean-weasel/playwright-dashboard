import Foundation

enum StaleLabelFormatter {
  static func reason(lastURL: String?, thresholdSeconds: Int) -> String {
    if lastURL == nil || lastURL == "about:blank" {
      return "No navigation"
    }

    guard thresholdSeconds > 0 else {
      return "Idle"
    }

    if thresholdSeconds % 60 == 0 {
      let minutes = thresholdSeconds / 60
      return "Idle \(minutes)m+"
    }

    return "Idle \(thresholdSeconds)s+"
  }
}

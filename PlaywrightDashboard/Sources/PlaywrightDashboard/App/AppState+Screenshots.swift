import Foundation

@MainActor
extension AppState {
  func saveScreenshot(_ session: SessionRecord) -> URL? {
    guard let data = session.lastScreenshot else {
      lastScreenshotSaveError = "No screenshot is available to save."
      return nil
    }

    let url = screenshotDirectoryProvider()
      .appendingPathComponent("\(session.sessionId)-\(Self.filenameTimestamp()).jpg")

    do {
      try data.write(to: url, options: .atomic)
      lastSavedScreenshotURL = url
      lastScreenshotSaveError = nil
      return url
    } catch {
      lastScreenshotSaveError = error.localizedDescription
      return nil
    }
  }

  func dismissScreenshotSaveError() {
    lastScreenshotSaveError = nil
  }

  private static func filenameTimestamp(date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: ".", with: "-")
  }
}

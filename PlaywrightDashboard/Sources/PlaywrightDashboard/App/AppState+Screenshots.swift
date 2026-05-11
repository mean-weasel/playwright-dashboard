import Foundation

@MainActor
extension AppState {
  func saveScreenshot(_ session: SessionRecord) -> URL? {
    guard let data = session.lastScreenshot else {
      lastScreenshotSaveError = "No screenshot is available to save."
      return nil
    }

    let sessionName = Self.sanitizedScreenshotPathComponent(session.sessionId)
    let url = screenshotDirectoryProvider()
      .appendingPathComponent("\(sessionName)-\(Self.filenameTimestamp()).jpg")

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

  static func sanitizedScreenshotPathComponent(_ text: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let scalars = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let sanitized =
      String(scalars)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "-")
    return sanitized.isEmpty ? "screenshot" : sanitized
  }
}

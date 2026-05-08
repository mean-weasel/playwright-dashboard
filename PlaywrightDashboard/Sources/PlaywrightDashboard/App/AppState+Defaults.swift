import Foundation
import SwiftData

extension AppState {
  var isSafeMode: Bool {
    safeModeProvider()
  }

  static func defaultScreenshotDirectory() -> URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }

  static func defaultModelContextSaver(_ modelContext: ModelContext?) throws {
    try modelContext?.save()
  }
}

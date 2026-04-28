import Foundation
import OSLog

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "LaunchAtLogin")

enum LaunchAtLoginManager {
  private static let plistPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(
      "Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist"
    ).path
  }()

  /// Whether the LaunchAgent plist currently exists on disk.
  static var isEnabled: Bool {
    FileManager.default.fileExists(atPath: plistPath)
  }

  /// Install the LaunchAgent plist so the app starts at login.
  static func enable() {
    let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]

    let plist: [String: Any] = [
      "Label": "com.neonwatty.PlaywrightDashboard",
      "ProgramArguments": [executablePath],
      "RunAtLoad": true,
      "KeepAlive": false,
    ]

    let dir = (plistPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)

    do {
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: URL(fileURLWithPath: plistPath))
      logger.info("LaunchAgent installed at \(plistPath)")
    } catch {
      logger.warning("Failed to write LaunchAgent: \(error.localizedDescription)")
    }
  }

  /// Remove the LaunchAgent plist.
  static func disable() {
    do {
      try FileManager.default.removeItem(atPath: plistPath)
      logger.info("LaunchAgent removed")
    } catch {
      logger.debug("LaunchAgent removal skipped: \(error.localizedDescription)")
    }
  }
}

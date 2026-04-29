import Foundation
import OSLog
import ServiceManagement

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "LaunchAtLogin")

enum LaunchAtLoginManager {
  private static let plistPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(
      "Library/LaunchAgents/com.neonwatty.PlaywrightDashboard.plist"
    ).path
  }()

  /// Whether the app is registered with Login Items, or with the legacy fallback plist.
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled || FileManager.default.fileExists(atPath: plistPath)
  }

  /// Register the app as a login item. Falls back to a LaunchAgent plist when
  /// running outside a normal app bundle, such as during local SwiftPM builds.
  static func enable() {
    do {
      try SMAppService.mainApp.register()
      removeLegacyLaunchAgent()
      logger.info("Registered login item with SMAppService")
    } catch {
      logger.warning(
        "SMAppService registration failed, falling back to LaunchAgent: \(error.localizedDescription)"
      )
      installLegacyLaunchAgent()
    }
  }

  /// Remove the login item registration and the legacy fallback plist.
  static func disable() {
    do {
      try SMAppService.mainApp.unregister()
      logger.info("Unregistered login item with SMAppService")
    } catch {
      logger.debug("SMAppService unregister skipped: \(error.localizedDescription)")
    }
    removeLegacyLaunchAgent()
  }

  private static func installLegacyLaunchAgent() {
    let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]

    let dir = (plistPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)

    do {
      let data = try PropertyListSerialization.data(
        fromPropertyList: legacyLaunchAgentPlist(executablePath: executablePath),
        format: .xml,
        options: 0
      )
      try data.write(to: URL(fileURLWithPath: plistPath))
      logger.info("LaunchAgent installed at \(plistPath)")
    } catch {
      logger.warning("Failed to write LaunchAgent: \(error.localizedDescription)")
    }
  }

  private static func removeLegacyLaunchAgent() {
    do {
      try FileManager.default.removeItem(atPath: plistPath)
      logger.info("LaunchAgent removed")
    } catch {
      logger.debug("LaunchAgent removal skipped: \(error.localizedDescription)")
    }
  }

  static func legacyLaunchAgentPlist(executablePath: String) -> [String: Any] {
    [
      "Label": "com.neonwatty.PlaywrightDashboard",
      "ProgramArguments": [executablePath],
      "RunAtLoad": true,
      "KeepAlive": false,
    ]
  }
}

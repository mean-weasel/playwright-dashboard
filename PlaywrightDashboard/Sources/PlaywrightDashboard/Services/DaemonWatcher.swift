import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "PlaywrightDashboard", category: "DaemonWatcher")

/// Watches the playwright daemon directory for `.session` file changes.
/// Provides an observable list of session file URLs that SwiftUI views can react to.
@Observable
@MainActor
final class DaemonWatcher {
  /// Current set of `.session` file URLs found in the daemon directory.
  private(set) var sessionFiles: [URL] = []

  /// The daemon directory being watched.
  static let daemonDirectory: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return
      home
      .appendingPathComponent("Library/Caches/ms-playwright/daemon", isDirectory: true)
  }()

  private var stream: FSEventsStream?
  private var directoryCheckTimer: DispatchSourceTimer?
  private let fileManager = FileManager.default

  init() {}

  /// Begin watching the daemon directory. If it doesn't exist yet, polls until it appears.
  func start() {
    let path = Self.daemonDirectory.path

    if fileManager.fileExists(atPath: path) {
      startWatching(path: path)
    } else {
      waitForDirectory(path: path)
    }
  }

  /// Stop watching and clean up.
  func stop() {
    stream?.stop()
    stream = nil
    directoryCheckTimer?.cancel()
    directoryCheckTimer = nil
  }

  // MARK: - Private

  /// Polls every 2 seconds waiting for the daemon directory to appear.
  private func waitForDirectory(path: String) {
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .seconds(2))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let directoryExists = FileManager.default.fileExists(atPath: path)
      guard directoryExists else { return }
      Task { @MainActor in
        self.directoryCheckTimer?.cancel()
        self.directoryCheckTimer = nil
        if self.stream == nil {
          self.startWatching(path: path)
        }
      }
    }
    directoryCheckTimer = timer
    timer.resume()
  }

  private func startWatching(path: String) {
    // Do an initial scan
    scanSessionFiles()

    // Start FSEvents stream
    let fsStream = FSEventsStream(path: path, debounceInterval: 0.5) { [weak self] _ in
      // Events arrived (already debounced) — rescan the directory
      guard let self else { return }
      Task { @MainActor in
        self.scanSessionFiles()
      }
    }
    stream = fsStream
    fsStream.start()
  }

  /// Scans the daemon directory recursively for `.session` files.
  private func scanSessionFiles() {
    let baseURL = Self.daemonDirectory

    guard fileManager.fileExists(atPath: baseURL.path) else {
      sessionFiles = []
      return
    }

    var found: [URL] = []

    // Enumerate subdirectories (workspace hashes)
    let hashDirs: [URL]
    do {
      hashDirs = try fileManager.contentsOfDirectory(
        at: baseURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      logger.error("Cannot read daemon directory: \(error.localizedDescription)")
      sessionFiles = []
      return
    }

    for dir in hashDirs {
      // Skip non-directories
      guard let values = try? dir.resourceValues(forKeys: [.isDirectoryKey]),
        values.isDirectory == true
      else {
        continue
      }

      // Skip user-data directories (browser profile dirs)
      if dir.lastPathComponent.contains("user-data") {
        continue
      }

      // Look for .session files in this hash directory
      guard
        let files = try? fileManager.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      else {
        continue
      }

      for file in files {
        if file.pathExtension == "session" {
          found.append(file)
        }
      }
    }

    sessionFiles = found.sorted { $0.path < $1.path }
  }
}

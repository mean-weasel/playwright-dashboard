import AppKit
import Foundation

@MainActor
enum SmokeRecordingExportRunner {
  static func startIfNeeded(
    arguments: SmokeLaunchArguments,
    appState: AppState
  ) {
    guard let resultURL = arguments.recordingExportResultURL else { return }
    Task {
      let result: SmokeRecordingExportResult
      do {
        result = try await run(
          selectedSessionId: arguments.selectedSessionId,
          appState: appState
        )
      } catch {
        result = SmokeRecordingExportResult(
          success: false,
          error: error.localizedDescription,
          recordingDirectory: nil,
          mp4Path: nil,
          frameCount: 0
        )
      }
      do {
        try write(result, to: resultURL)
      } catch {
        fputs("Failed to write smoke recording result: \(error.localizedDescription)\n", stderr)
      }
      NSApplication.shared.terminate(nil)
    }
  }

  private static func run(
    selectedSessionId: String?,
    appState: AppState
  ) async throws -> SmokeRecordingExportResult {
    let session = try await waitForSession(selectedSessionId, appState: appState)
    let snapshot = ExpandedRecordingSessionSnapshot(
      sessionId: session.sessionId,
      displayName: session.displayName,
      targetId: session.selectedTargetId,
      initialURL: session.lastURL,
      initialTitle: session.lastTitle
    )
    let writer = ExpandedRecordingWriter(snapshot: snapshot)
    _ = try await writer.start()
    let connection = CDPPageConnection(port: session.cdpPort, targetId: session.selectedTargetId)
    var latestFrame: CDPClient.ScreencastFrame?
    var frameCount = 0

    do {
      let frames = try await connection.startScreencast(
        quality: DashboardSettings.expandedQuality())
      for try await frame in frames {
        latestFrame = frame
        frameCount = try await writer.append(frame: frame)
        if frameCount >= 12 { break }
      }
      await connection.close()
      let finishedDirectory = try await writer.finish(
        finalURL: latestFrame?.url,
        finalTitle: latestFrame?.title
      )
      let mp4 = try await ExpandedRecordingVideoExporter().exportMP4(from: finishedDirectory)
      return SmokeRecordingExportResult(
        success: true,
        error: nil,
        recordingDirectory: finishedDirectory.path,
        mp4Path: mp4.path,
        frameCount: frameCount
      )
    } catch {
      try? await writer.cancel()
      await connection.close()
      throw error
    }
  }

  private static func waitForSession(
    _ selectedSessionId: String?,
    appState: AppState
  ) async throws -> SessionRecord {
    let started = ContinuousClock.now
    while started.duration(to: .now) < .seconds(15) {
      if let selectedSessionId,
        let session = appState.sessions.first(where: { $0.sessionId == selectedSessionId })
      {
        guard session.cdpPort > 0 else { throw SmokeRecordingExportError.noCDPPort }
        return session
      }
      if selectedSessionId == nil,
        let session = appState.sessions.first(where: { $0.cdpPort > 0 })
      {
        return session
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    throw SmokeRecordingExportError.sessionNotFound
  }

  private static func write(_ result: SmokeRecordingExportResult, to url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: url, options: .atomic)
  }
}

struct SmokeRecordingExportResult: Codable, Equatable {
  let success: Bool
  let error: String?
  let recordingDirectory: String?
  let mp4Path: String?
  let frameCount: Int
}

enum SmokeRecordingExportError: LocalizedError {
  case sessionNotFound
  case noCDPPort

  var errorDescription: String? {
    switch self {
    case .sessionNotFound: "Timed out waiting for a smoke session."
    case .noCDPPort: "Smoke session has no CDP port."
    }
  }
}

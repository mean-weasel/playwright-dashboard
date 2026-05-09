import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("ExpandedRecordingWriter")
struct ExpandedRecordingWriterTests {

  @Test("writes frames and manifest")
  func writesFramesAndManifest() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = ExpandedRecordingWriter(
      snapshot: snapshot,
      baseDirectory: tempDirectory,
      now: { startedAt }
    )

    let directory = try await writer.start()
    let frameCount = try await writer.append(
      frame: CDPClient.ScreencastFrame(
        jpeg: Data([0x01, 0x02, 0x03]),
        sessionId: 7,
        url: "https://example.com",
        title: "Example",
        targetId: "target-1"
      ))
    let finishedDirectory = try await writer.finish(
      finalURL: "https://example.com/done",
      finalTitle: "Done"
    )

    #expect(frameCount == 1)
    #expect(finishedDirectory == directory)
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("frame-000001.jpg").path))

    let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(ExpandedRecordingManifest.self, from: manifestData)

    #expect(manifest.version == 1)
    #expect(manifest.sessionId == "session-1")
    #expect(manifest.displayName == "Session One")
    #expect(manifest.targetId == "target-1")
    #expect(manifest.initialURL == "https://example.com")
    #expect(manifest.finalURL == "https://example.com/done")
    #expect(manifest.frameCount == 1)
    #expect(manifest.frames.first?.filename == "frame-000001.jpg")
  }

  @Test("cancel removes partial recording")
  func cancelRemovesPartialRecording() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let writer = ExpandedRecordingWriter(snapshot: snapshot, baseDirectory: tempDirectory)

    let directory = try await writer.start()
    try await writer.append(
      frame: CDPClient.ScreencastFrame(
        jpeg: Data([0x01]),
        sessionId: 7,
        url: nil,
        title: nil
      ))
    try await writer.cancel()

    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test("rejects frames after duration limit")
  func rejectsFramesAfterDurationLimit() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let writer = ExpandedRecordingWriter(
      snapshot: snapshot,
      baseDirectory: tempDirectory,
      limits: .init(maxDuration: 10, maxBytes: 1_000)
    )

    await #expect(throws: ExpandedRecordingWriter.RecordingError.self) {
      try await writer.append(
        frame: frame(bytes: [0x01]),
        receivedAt: Date().addingTimeInterval(11)
      )
    }
  }

  @Test("rejects frames that exceed size limit")
  func rejectsFramesAfterSizeLimit() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let writer = ExpandedRecordingWriter(
      snapshot: snapshot,
      baseDirectory: tempDirectory,
      limits: .init(maxDuration: 600, maxBytes: 3)
    )

    _ = try await writer.append(frame: frame(bytes: [0x01, 0x02]))

    await #expect(throws: ExpandedRecordingWriter.RecordingError.self) {
      try await writer.append(frame: frame(bytes: [0x03, 0x04]))
    }
  }

  @Test("sanitizes recording directory names")
  func sanitizesRecordingDirectoryNames() {
    #expect(
      ExpandedRecordingWriter.sanitizedPathComponent("Admin / Users: Audit")
        == "Admin---Users--Audit")
    #expect(ExpandedRecordingWriter.sanitizedPathComponent("  ") == "recording")
  }

  private var snapshot: ExpandedRecordingSessionSnapshot {
    ExpandedRecordingSessionSnapshot(
      sessionId: "session-1",
      displayName: "Session One",
      targetId: "target-1",
      initialURL: "https://example.com",
      initialTitle: "Example"
    )
  }

  private func frame(bytes: [UInt8]) -> CDPClient.ScreencastFrame {
    CDPClient.ScreencastFrame(
      jpeg: Data(bytes),
      sessionId: 7,
      url: nil,
      title: nil
    )
  }
}

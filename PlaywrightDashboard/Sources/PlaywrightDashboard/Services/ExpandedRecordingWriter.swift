import Foundation

actor ExpandedRecordingWriter {
  private let snapshot: ExpandedRecordingSessionSnapshot
  private let baseDirectory: URL
  private let fileManager: FileManager
  private let now: @Sendable () -> Date
  private let startedAt: Date
  private var directoryURL: URL?
  private var frames: [ExpandedRecordingManifest.Frame] = []
  private var isFinished = false

  init(
    snapshot: ExpandedRecordingSessionSnapshot,
    baseDirectory: URL = ExpandedRecordingWriter.defaultBaseDirectory(),
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.snapshot = snapshot
    self.baseDirectory = baseDirectory
    self.fileManager = fileManager
    self.now = now
    self.startedAt = now()
  }

  func start() throws -> URL {
    guard directoryURL == nil else {
      return directoryURL!
    }

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    let directory = uniqueRecordingDirectory()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    directoryURL = directory
    return directory
  }

  @discardableResult
  func append(frame: CDPClient.ScreencastFrame, receivedAt: Date? = nil) throws -> Int {
    guard !isFinished else { throw RecordingError.alreadyFinished }
    let directory = try activeDirectory()
    let index = frames.count + 1
    let filename = String(format: "frame-%06d.jpg", index)
    let url = directory.appendingPathComponent(filename)
    try frame.jpeg.write(to: url, options: .atomic)
    frames.append(
      ExpandedRecordingManifest.Frame(
        index: index,
        filename: filename,
        timestamp: receivedAt ?? now(),
        url: frame.url,
        title: frame.title
      ))
    return frames.count
  }

  @discardableResult
  func finish(finalURL: String?, finalTitle: String?) throws -> URL {
    guard !isFinished else { throw RecordingError.alreadyFinished }
    let directory = try activeDirectory()
    let endedAt = now()
    let manifest = ExpandedRecordingManifest(
      version: 1,
      sessionId: snapshot.sessionId,
      displayName: snapshot.displayName,
      targetId: snapshot.targetId,
      initialURL: snapshot.initialURL,
      initialTitle: snapshot.initialTitle,
      finalURL: finalURL,
      finalTitle: finalTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      frameCount: frames.count,
      frames: frames
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(manifest)
    try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    isFinished = true
    return directory
  }

  func cancel() throws {
    guard let directoryURL else { return }
    try? fileManager.removeItem(at: directoryURL)
    isFinished = true
  }

  private func activeDirectory() throws -> URL {
    if let directoryURL { return directoryURL }
    return try start()
  }

  private func uniqueRecordingDirectory() -> URL {
    let stamp = Self.directoryDateFormatter.string(from: startedAt)
    let name = "\(Self.sanitizedPathComponent(snapshot.displayName))-\(stamp)"
    var candidate = baseDirectory.appendingPathComponent(name, isDirectory: true)
    var suffix = 2
    while fileManager.fileExists(atPath: candidate.path) {
      candidate = baseDirectory.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
      suffix += 1
    }
    return candidate
  }

  static func defaultBaseDirectory() -> URL {
    let downloads =
      FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return downloads.appendingPathComponent("PlaywrightDashboard Recordings", isDirectory: true)
  }

  static func sanitizedPathComponent(_ text: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let scalars = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let sanitized =
      String(scalars)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "-")
    return sanitized.isEmpty ? "recording" : sanitized
  }

  private static let directoryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()

  enum RecordingError: Error, LocalizedError, Equatable {
    case alreadyFinished

    var errorDescription: String? {
      switch self {
      case .alreadyFinished: "Recording has already finished."
      }
    }
  }
}

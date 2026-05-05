import Foundation

struct ExpandedRecordingSessionSnapshot: Codable, Equatable, Sendable {
  let sessionId: String
  let displayName: String
  let targetId: String?
  let initialURL: String?
  let initialTitle: String?
}

struct ExpandedRecordingManifest: Codable, Equatable, Sendable {
  struct Frame: Codable, Equatable, Sendable {
    let index: Int
    let filename: String
    let timestamp: Date
    let url: String?
    let title: String?
  }

  let version: Int
  let sessionId: String
  let displayName: String
  let targetId: String?
  let initialURL: String?
  let initialTitle: String?
  let finalURL: String?
  let finalTitle: String?
  let startedAt: Date
  let endedAt: Date
  let frameCount: Int
  let frames: [Frame]
}

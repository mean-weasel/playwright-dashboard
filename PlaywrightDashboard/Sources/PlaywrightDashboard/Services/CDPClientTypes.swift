import Foundation

extension CDPClient {
  struct ScreenshotResult: Sendable {
    let jpeg: Data
    let url: String?
    let title: String?
    let targetId: String?
    let pageTargets: [CDPPageTarget]

    init(
      jpeg: Data,
      url: String?,
      title: String?,
      targetId: String? = nil,
      pageTargets: [CDPPageTarget] = []
    ) {
      self.jpeg = jpeg
      self.url = url
      self.title = title
      self.targetId = targetId
      self.pageTargets = pageTargets
    }
  }

  enum CDPError: Error, LocalizedError {
    case noPages
    case invalidResponse
    case timeout
    case protocolError(String)

    var errorDescription: String? {
      switch self {
      case .noPages: "No pages available on this CDP port"
      case .invalidResponse: "Invalid screenshot response from CDP"
      case .timeout: "Timed out waiting for CDP response"
      case .protocolError(let msg): "CDP error: \(msg)"
      }
    }
  }
}

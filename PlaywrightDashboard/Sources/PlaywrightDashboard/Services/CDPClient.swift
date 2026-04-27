import Foundation

/// Lightweight CDP (Chrome DevTools Protocol) client using URLSessionWebSocketTask.
/// Connects to a single page's WebSocket endpoint and sends commands.
actor CDPClient {
  private let port: Int
  private var nextId = 1
  private let session = URLSession(configuration: .ephemeral)
  private let maxResponseMessages = 10

  init(port: Int) {
    self.port = port
  }

  // MARK: - Page Discovery

  struct PageInfo: Decodable {
    let id: String
    let type: String
    let url: String?
    let title: String?
    let webSocketDebuggerUrl: String?
  }

  /// Fetches the list of pages from the CDP HTTP endpoint.
  func listPages() async throws -> [PageInfo] {
    let url = URL(string: "http://localhost:\(port)/json/list")!
    let (data, _) = try await session.data(from: url)
    return try JSONDecoder().decode([PageInfo].self, from: data)
  }

  // MARK: - Screenshot

  struct ScreenshotResult: Sendable {
    let jpeg: Data
    let url: String?
    let title: String?
  }

  /// Captures a JPEG screenshot of the first available page.
  func captureScreenshot(quality: Int = 50) async throws -> ScreenshotResult {
    let clampedQuality = max(0, min(100, quality))
    let pages = try await listPages()

    // Pick the first "page" type that has a real URL (not about:blank)
    guard
      let page = pages.first(where: {
        $0.type == "page" && $0.url != nil && $0.url != "about:blank"
      }) ?? pages.first(where: { $0.type == "page" }),
      let wsURLString = page.webSocketDebuggerUrl,
      let wsURL = URL(string: wsURLString)
    else {
      throw CDPError.noPages
    }

    let ws = session.webSocketTask(with: wsURL)
    ws.resume()
    defer { ws.cancel(with: .normalClosure, reason: nil) }

    let id = nextId
    nextId += 1

    // Send Page.captureScreenshot
    let command: [String: Any] = [
      "id": id,
      "method": "Page.captureScreenshot",
      "params": ["format": "jpeg", "quality": clampedQuality],
    ]
    let commandData = try JSONSerialization.data(withJSONObject: command)
    guard let commandString = String(data: commandData, encoding: .utf8) else {
      throw CDPError.invalidResponse
    }
    try await ws.send(.string(commandString))

    // Read response (may need to skip CDP events)
    for _ in 0..<maxResponseMessages {
      let message = try await ws.receive()
      switch message {
      case .string(let text):
        guard let responseData = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
          let responseId = json["id"] as? Int,
          responseId == id
        else {
          continue  // Skip CDP events, wait for our response
        }

        // Check for CDP protocol-level errors
        if let error = json["error"] as? [String: Any] {
          let message = error["message"] as? String ?? "Unknown CDP error"
          throw CDPError.protocolError(message)
        }

        guard let result = json["result"] as? [String: Any],
          let base64String = result["data"] as? String,
          let jpeg = Data(base64Encoded: base64String)
        else {
          throw CDPError.invalidResponse
        }

        return ScreenshotResult(jpeg: jpeg, url: page.url, title: page.title)

      case .data:
        continue  // Skip binary messages

      @unknown default:
        continue
      }
    }

    throw CDPError.timeout
  }

  // MARK: - Errors

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

import Foundation

/// Lightweight CDP (Chrome DevTools Protocol) client using URLSessionWebSocketTask.
/// Connects to a single page's WebSocket endpoint and sends commands.
actor CDPClient {
  private let port: Int
  private var nextId = 1
  private let session: URLSession
  private let maxResponseMessages = 10
  private let requestTimeout: Duration

  init(port: Int, requestTimeout: Duration = .seconds(3)) {
    self.port = port
    self.requestTimeout = requestTimeout
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout.timeInterval
    configuration.timeoutIntervalForResource = requestTimeout.timeInterval
    self.session = URLSession(configuration: configuration)
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
    let (data, _) = try await withTimeout(requestTimeout) {
      try await self.session.data(from: url)
    }
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
      let page = Self.pageForScreenshot(from: pages),
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
    try await sendWebSocketMessage(.string(commandString), to: ws)

    // Read response (may need to skip CDP events)
    for _ in 0..<maxResponseMessages {
      let message = try await receiveWebSocketMessage(from: ws)
      switch message {
      case .string(let text):
        if let result = try Self.parseScreenshotResponse(text, expectedId: id, page: page) {
          return result
        }

      case .data:
        continue  // Skip binary messages

      @unknown default:
        continue
      }
    }

    throw CDPError.timeout
  }

  // MARK: - Input

  func dispatchMouseClick(x: Double, y: Double) async throws {
    try await sendCommand(
      method: "Input.dispatchMouseEvent",
      params: Self.mouseEventParams(type: "mousePressed", x: x, y: y, button: "left", clickCount: 1)
    )
    try await sendCommand(
      method: "Input.dispatchMouseEvent",
      params: Self.mouseEventParams(
        type: "mouseReleased", x: x, y: y, button: "left", clickCount: 1)
    )
  }

  func dispatchMouseWheel(x: Double, y: Double, deltaX: Double, deltaY: Double) async throws {
    try await sendCommand(
      method: "Input.dispatchMouseEvent",
      params: Self.mouseWheelParams(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
    )
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

  static func parseScreenshotResponse(
    _ text: String,
    expectedId: Int,
    page: PageInfo
  ) throws -> ScreenshotResult? {
    guard let responseData = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let responseId = json["id"] as? Int,
      responseId == expectedId
    else {
      return nil
    }

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
  }

  private func sendCommand(method: String, params: [String: Any]) async throws {
    let pages = try await listPages()
    guard
      let page = Self.pageForScreenshot(from: pages),
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
    let commandString = try Self.commandString(id: id, method: method, params: params)
    try await sendWebSocketMessage(.string(commandString), to: ws)

    for _ in 0..<maxResponseMessages {
      let message = try await receiveWebSocketMessage(from: ws)
      if case .string(let text) = message, try Self.isCommandResponse(text, expectedId: id) {
        return
      }
    }

    throw CDPError.timeout
  }

  private func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw CDPError.timeout
      }
      defer { group.cancelAll() }

      guard let result = try await group.next() else {
        throw CDPError.timeout
      }
      return result
    }
  }

  private func sendWebSocketMessage(
    _ message: URLSessionWebSocketTask.Message,
    to webSocket: URLSessionWebSocketTask
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await webSocket.send(message)
      }
      group.addTask {
        try await Task.sleep(for: self.requestTimeout)
        webSocket.cancel(with: .goingAway, reason: nil)
        throw CDPError.timeout
      }
      defer { group.cancelAll() }

      _ = try await group.next()
    }
  }

  private func receiveWebSocketMessage(
    from webSocket: URLSessionWebSocketTask
  ) async throws -> URLSessionWebSocketTask.Message {
    try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
      group.addTask {
        try await webSocket.receive()
      }
      group.addTask {
        try await Task.sleep(for: self.requestTimeout)
        webSocket.cancel(with: .goingAway, reason: nil)
        throw CDPError.timeout
      }
      defer { group.cancelAll() }

      guard let result = try await group.next() else {
        throw CDPError.timeout
      }
      return result
    }
  }
}

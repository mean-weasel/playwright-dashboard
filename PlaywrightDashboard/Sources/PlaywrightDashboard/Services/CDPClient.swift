import Foundation

/// Lightweight CDP (Chrome DevTools Protocol) client using URLSessionWebSocketTask.
/// Connects to a single page's WebSocket endpoint and sends commands.
actor CDPClient {
  let port: Int
  var nextId = 1
  let session: URLSession
  let requestTimeout: Duration

  init(port: Int, requestTimeout: Duration = .seconds(3)) {
    self.port = port
    self.requestTimeout = requestTimeout
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout.timeInterval
    configuration.timeoutIntervalForResource = requestTimeout.timeInterval
    self.session = URLSession(configuration: configuration)
  }

  struct PageInfo: Decodable {
    let id: String
    let type: String
    let url: String?
    let title: String?
    let webSocketDebuggerUrl: String?
  }

  /// Fetches the list of pages from the CDP HTTP endpoint.
  func listPages() async throws -> [PageInfo] {
    let url = try Self.cdpHTTPURL(port: port, path: "/json/list")
    let (data, response) = try await withTimeout(requestTimeout) {
      try await self.session.data(from: url)
    }
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw CDPError.invalidResponse
    }
    let pages = try JSONDecoder().decode([PageInfo].self, from: data)
    for webSocketDebuggerURL in pages.compactMap(\.webSocketDebuggerUrl) {
      _ = try Self.validatedWebSocketDebuggerURL(webSocketDebuggerURL, sourceURL: url)
    }
    return pages
  }

  /// Captures a JPEG screenshot of the first available page.
  func captureScreenshot(quality: Int = 50, targetId: String? = nil) async throws
    -> ScreenshotResult
  {
    let clampedQuality = max(0, min(100, quality))
    let pages = try await listPages()
    let pageTargets = CDPPageTargetSelection.selectableTargets(from: pages)
    let sourceURL = try Self.cdpHTTPURL(port: port, path: "/json/list")

    guard
      let pageTarget = CDPPageTargetSelection.selectedTarget(
        from: pageTargets,
        preferredTargetId: targetId
      )
    else {
      throw CDPError.noPages
    }
    let wsURL = try Self.validatedWebSocketDebuggerURL(
      pageTarget.webSocketDebuggerUrl,
      sourceURL: sourceURL
    )

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

    return try await waitForScreenshotResponse(
      from: ws,
      id: id,
      pageTarget: pageTarget,
      pageTargets: pageTargets
    )
  }

  func dispatchMouseClick(x: Double, y: Double) async throws {
    try await sendCommands([
      (
        method: "Input.dispatchMouseEvent",
        params: Self.mouseEventParams(
          type: "mousePressed", x: x, y: y, button: "left", clickCount: 1)
      ),
      (
        method: "Input.dispatchMouseEvent",
        params: Self.mouseEventParams(
          type: "mouseReleased", x: x, y: y, button: "left", clickCount: 1)
      ),
    ])
  }

  func dispatchMouseWheel(x: Double, y: Double, deltaX: Double, deltaY: Double) async throws {
    try await sendCommand(
      method: "Input.dispatchMouseEvent",
      params: Self.mouseWheelParams(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
    )
  }

  func dispatchKeyPress(_ input: KeyEventInput) async throws {
    let downType = input.isPrintable ? "keyDown" : "rawKeyDown"
    try await sendCommands([
      (
        method: "Input.dispatchKeyEvent",
        params: Self.keyEventParams(type: downType, input: input, includeText: input.isPrintable)
      ),
      (
        method: "Input.dispatchKeyEvent",
        params: Self.keyEventParams(type: "keyUp", input: input, includeText: false)
      ),
    ])
  }

  func dispatchMouseClick(x: Double, y: Double, targetId: String?) async throws {
    try await sendCommands(
      [
        (
          method: "Input.dispatchMouseEvent",
          params: Self.mouseEventParams(
            type: "mousePressed", x: x, y: y, button: "left", clickCount: 1)
        ),
        (
          method: "Input.dispatchMouseEvent",
          params: Self.mouseEventParams(
            type: "mouseReleased", x: x, y: y, button: "left", clickCount: 1)
        ),
      ], targetId: targetId)
  }

  func dispatchMouseWheel(
    x: Double,
    y: Double,
    deltaX: Double,
    deltaY: Double,
    targetId: String?
  ) async throws {
    try await sendCommand(
      method: "Input.dispatchMouseEvent",
      params: Self.mouseWheelParams(x: x, y: y, deltaX: deltaX, deltaY: deltaY),
      targetId: targetId
    )
  }

  func dispatchKeyPress(_ input: KeyEventInput, targetId: String?) async throws {
    let downType = input.isPrintable ? "keyDown" : "rawKeyDown"
    try await sendCommands(
      [
        (
          method: "Input.dispatchKeyEvent",
          params: Self.keyEventParams(type: downType, input: input, includeText: input.isPrintable)
        ),
        (
          method: "Input.dispatchKeyEvent",
          params: Self.keyEventParams(type: "keyUp", input: input, includeText: false)
        ),
      ], targetId: targetId)
  }

}

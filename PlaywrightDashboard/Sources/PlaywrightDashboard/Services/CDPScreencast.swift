import Foundation

extension CDPClient {
  struct ScreencastFrame: Sendable {
    let jpeg: Data
    let sessionId: Int
    let url: String?
    let title: String?
    let targetId: String?
    let pageTargets: [CDPPageTarget]

    init(
      jpeg: Data,
      sessionId: Int,
      url: String?,
      title: String?,
      targetId: String? = nil,
      pageTargets: [CDPPageTarget] = []
    ) {
      self.jpeg = jpeg
      self.sessionId = sessionId
      self.url = url
      self.title = title
      self.targetId = targetId
      self.pageTargets = pageTargets
    }
  }

  func screencastFrames(
    quality: Int = 60
  ) -> AsyncThrowingStream<ScreencastFrame, Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
      let task = Task {
        do {
          try await runScreencast(quality: quality, continuation: continuation)
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  static func parseScreencastFrame(_ text: String) throws -> ScreencastFrame? {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    if let error = json["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown CDP error"
      throw CDPError.protocolError(message)
    }

    guard json["method"] as? String == "Page.screencastFrame",
      let params = json["params"] as? [String: Any],
      let sessionId = params["sessionId"] as? Int,
      let base64String = params["data"] as? String,
      let jpeg = Data(base64Encoded: base64String)
    else {
      return nil
    }

    return ScreencastFrame(jpeg: jpeg, sessionId: sessionId, url: nil, title: nil)
  }

  static func screencastStartParams(quality: Int) -> [String: Any] {
    [
      "format": "jpeg",
      "quality": DashboardSettings.clampedQuality(quality),
      "everyNthFrame": 1,
    ]
  }

  private func runScreencast(
    quality: Int,
    continuation: AsyncThrowingStream<ScreencastFrame, Error>.Continuation
  ) async throws {
    let pages = try await listPages()
    let pageTargets = CDPPageTargetSelection.selectableTargets(from: pages)
    let sourceURL = try Self.cdpHTTPURL(port: port, path: "/json/list")
    guard
      let pageTarget = CDPPageTargetSelection.selectedTarget(
        from: pageTargets,
        preferredTargetId: nil
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

    let startId = nextId
    nextId += 1
    try await sendWebSocketCommand(
      id: startId,
      method: "Page.startScreencast",
      params: Self.screencastStartParams(quality: quality),
      to: ws
    )
    try await waitForCommandResponseIgnoringEvents(from: ws, id: startId)

    do {
      while !Task.isCancelled {
        let message = try await receiveWebSocketMessage(from: ws)
        guard case .string(let text) = message else { continue }
        if let frame = try Self.parseScreencastFrame(text) {
          continuation.yield(
            ScreencastFrame(
              jpeg: frame.jpeg,
              sessionId: frame.sessionId,
              url: pageTarget.url,
              title: pageTarget.title,
              targetId: pageTarget.id,
              pageTargets: pageTargets
            )
          )
          try await acknowledgeScreencastFrame(frame.sessionId, on: ws)
        }
      }
    } catch is CancellationError {
      try await stopScreencast(on: ws)
      throw CancellationError()
    } catch {
      try? await stopScreencast(on: ws)
      throw error
    }

    try await stopScreencast(on: ws)
  }

  private func acknowledgeScreencastFrame(
    _ sessionId: Int,
    on ws: URLSessionWebSocketTask
  ) async throws {
    let id = nextId
    nextId += 1
    try await sendWebSocketCommand(
      id: id,
      method: "Page.screencastFrameAck",
      params: ["sessionId": sessionId],
      to: ws
    )
  }

  private func stopScreencast(on ws: URLSessionWebSocketTask) async throws {
    let id = nextId
    nextId += 1
    try await sendWebSocketCommand(
      id: id,
      method: "Page.stopScreencast",
      params: [:],
      to: ws
    )
  }

  private func sendWebSocketCommand(
    id: Int,
    method: String,
    params: [String: Any],
    to ws: URLSessionWebSocketTask
  ) async throws {
    let command = try Self.commandString(id: id, method: method, params: params)
    try await sendWebSocketMessage(.string(command), to: ws)
  }

  private func waitForCommandResponseIgnoringEvents(
    from webSocket: URLSessionWebSocketTask,
    id: Int
  ) async throws {
    try await withTimeout(requestTimeout) {
      while !Task.isCancelled {
        let message = try await self.receiveWebSocketMessage(from: webSocket)
        if case .string(let text) = message, try Self.isCommandResponse(text, expectedId: id) {
          return
        }
      }

      throw CDPError.timeout
    }
  }
}

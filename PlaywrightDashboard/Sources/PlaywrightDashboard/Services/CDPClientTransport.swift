import Foundation

extension CDPClient {
  func sendCommand(
    method: String,
    params: [String: Any],
    targetId: String? = nil
  ) async throws {
    try await sendCommands([(method: method, params: params)], targetId: targetId)
  }

  func sendCommandReturningResponse(
    method: String,
    params: [String: Any],
    targetId: String? = nil
  ) async throws -> String {
    let pages = try await listPages()
    guard
      let pageTarget = CDPPageTargetSelection.selectedTarget(
        from: pages,
        preferredTargetId: targetId
      ),
      let wsURLString = pageTarget.webSocketDebuggerUrl,
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
    return try await waitForCommandResponse(from: ws, id: id)
  }

  func sendCommands(
    _ commands: [(method: String, params: [String: Any])],
    targetId: String? = nil
  ) async throws {
    let pages = try await listPages()
    guard
      let pageTarget = CDPPageTargetSelection.selectedTarget(
        from: pages,
        preferredTargetId: targetId
      ),
      let wsURLString = pageTarget.webSocketDebuggerUrl,
      let wsURL = URL(string: wsURLString)
    else {
      throw CDPError.noPages
    }

    let ws = session.webSocketTask(with: wsURL)
    ws.resume()
    defer { ws.cancel(with: .normalClosure, reason: nil) }

    for command in commands {
      let id = nextId
      nextId += 1
      let commandString = try Self.commandString(
        id: id, method: command.method, params: command.params)
      try await sendWebSocketMessage(.string(commandString), to: ws)
      _ = try await waitForCommandResponse(from: ws, id: id)
    }
  }

  func waitForScreenshotResponse(
    from webSocket: URLSessionWebSocketTask,
    id: Int,
    pageTarget: CDPPageTarget,
    pageTargets: [CDPPageTarget]
  ) async throws -> ScreenshotResult {
    try await withTimeout(requestTimeout) {
      while !Task.isCancelled {
        let message = try await self.receiveWebSocketMessage(from: webSocket)
        switch message {
        case .string(let text):
          if let result = try Self.parseScreenshotResponse(
            text,
            expectedId: id,
            pageTarget: pageTarget,
            pageTargets: pageTargets
          ) {
            return result
          }

        case .data:
          continue

        @unknown default:
          continue
        }
      }

      throw CDPError.timeout
    }
  }

  func waitForCommandResponse(
    from webSocket: URLSessionWebSocketTask,
    id: Int
  ) async throws -> String {
    try await withTimeout(requestTimeout) {
      while !Task.isCancelled {
        let message = try await self.receiveWebSocketMessage(from: webSocket)
        if case .string(let text) = message, try Self.isCommandResponse(text, expectedId: id) {
          return text
        }
      }

      throw CDPError.timeout
    }
  }

  func withTimeout<T: Sendable>(
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

  func sendWebSocketMessage(
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

  func receiveWebSocketMessage(
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

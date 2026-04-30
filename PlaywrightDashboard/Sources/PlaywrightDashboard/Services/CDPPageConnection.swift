import Foundation

actor CDPPageConnection {
  private let port: Int
  private let requestTimeout: Duration
  private let session: URLSession
  private var webSocket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var nextId = 1
  private var pendingCommands: [Int: CheckedContinuation<Void, Error>] = [:]
  private var frameContinuation: AsyncThrowingStream<CDPClient.ScreencastFrame, Error>.Continuation?
  private var page: CDPClient.PageInfo?
  private var isClosed = false

  init(port: Int, requestTimeout: Duration = .seconds(3)) {
    self.port = port
    self.requestTimeout = requestTimeout
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout.timeInterval
    configuration.timeoutIntervalForResource = requestTimeout.timeInterval
    self.session = URLSession(configuration: configuration)
  }

  func startScreencast(quality: Int) async throws -> AsyncThrowingStream<
    CDPClient.ScreencastFrame, Error
  > {
    try await connectIfNeeded()

    var continuation: AsyncThrowingStream<CDPClient.ScreencastFrame, Error>.Continuation!
    let stream = AsyncThrowingStream<CDPClient.ScreencastFrame, Error>(
      bufferingPolicy: .bufferingNewest(2)
    ) { newContinuation in
      continuation = newContinuation
      newContinuation.onTermination = { [weak self] _ in
        Task {
          await self?.close()
        }
      }
    }
    frameContinuation = continuation

    try await sendCommandAndWait(
      method: "Page.startScreencast",
      params: CDPClient.screencastStartParams(quality: quality)
    )
    return stream
  }

  func dispatchMouseClick(x: Double, y: Double) async throws {
    try await sendCommandAndWait(
      method: "Input.dispatchMouseEvent",
      params: CDPClient.mouseEventParams(
        type: "mousePressed", x: x, y: y, button: "left", clickCount: 1)
    )
    try await sendCommandAndWait(
      method: "Input.dispatchMouseEvent",
      params: CDPClient.mouseEventParams(
        type: "mouseReleased", x: x, y: y, button: "left", clickCount: 1)
    )
  }

  func dispatchMouseWheel(x: Double, y: Double, deltaX: Double, deltaY: Double) async throws {
    try await sendCommandAndWait(
      method: "Input.dispatchMouseEvent",
      params: CDPClient.mouseWheelParams(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
    )
  }

  func dispatchKeyPress(_ input: CDPClient.KeyEventInput) async throws {
    let downType = input.isPrintable ? "keyDown" : "rawKeyDown"
    try await sendCommandAndWait(
      method: "Input.dispatchKeyEvent",
      params: CDPClient.keyEventParams(
        type: downType, input: input, includeText: input.isPrintable)
    )
    try await sendCommandAndWait(
      method: "Input.dispatchKeyEvent",
      params: CDPClient.keyEventParams(type: "keyUp", input: input, includeText: false)
    )
  }

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    try? await sendCommand(method: "Page.stopScreencast", params: [:])
    receiveTask?.cancel()
    receiveTask = nil
    webSocket?.cancel(with: .normalClosure, reason: nil)
    webSocket = nil
    frameContinuation?.finish()
    frameContinuation = nil

    for continuation in pendingCommands.values {
      continuation.resume(throwing: CDPClient.CDPError.timeout)
    }
    pendingCommands.removeAll()
  }

  private func connectIfNeeded() async throws {
    if webSocket != nil { return }

    let client = CDPClient(port: port, requestTimeout: requestTimeout)
    let pages = try await client.listPages()
    guard
      let selectedPage = CDPClient.pageForScreenshot(from: pages),
      let wsURLString = selectedPage.webSocketDebuggerUrl,
      let wsURL = URL(string: wsURLString)
    else {
      throw CDPClient.CDPError.noPages
    }

    page = selectedPage
    let ws = session.webSocketTask(with: wsURL)
    webSocket = ws
    ws.resume()
    receiveTask = Task { [weak self] in
      await self?.receiveLoop()
    }
  }

  private func receiveLoop() async {
    while !Task.isCancelled {
      guard let webSocket else { break }
      do {
        let message = try await webSocket.receive()
        if case .string(let text) = message {
          try await handleMessage(text)
        }
      } catch is CancellationError {
        break
      } catch {
        await failAll(error)
        break
      }
    }
  }

  private func handleMessage(_ text: String) async throws {
    if let id = Self.responseId(from: text),
      let continuation = pendingCommands.removeValue(forKey: id)
    {
      if let message = Self.protocolErrorMessage(from: text) {
        continuation.resume(throwing: CDPClient.CDPError.protocolError(message))
      } else {
        continuation.resume()
      }
      return
    }

    guard let frame = try CDPClient.parseScreencastFrame(text) else { return }
    frameContinuation?.yield(
      CDPClient.ScreencastFrame(
        jpeg: frame.jpeg,
        sessionId: frame.sessionId,
        url: page?.url,
        title: page?.title
      )
    )
    try await sendCommand(
      method: "Page.screencastFrameAck",
      params: ["sessionId": frame.sessionId]
    )
  }

  private func sendCommandAndWait(method: String, params: [String: Any]) async throws {
    try await connectIfNeeded()
    let id = nextCommandId()
    let command = try CDPClient.commandString(id: id, method: method, params: params)

    try await withCheckedThrowingContinuation { continuation in
      pendingCommands[id] = continuation
      Task {
        do {
          try await self.sendText(command)
        } catch {
          await self.failPendingCommand(id: id, error: error)
        }
      }
      Task {
        do {
          try await Task.sleep(for: requestTimeout)
          await self.failPendingCommand(id: id, error: CDPClient.CDPError.timeout)
        } catch {}
      }
    }
  }

  private func sendCommand(method: String, params: [String: Any]) async throws {
    try await connectIfNeeded()
    let command = try CDPClient.commandString(id: nextCommandId(), method: method, params: params)
    try await sendText(command)
  }

  private func sendText(_ text: String) async throws {
    guard let webSocket else { throw CDPClient.CDPError.invalidResponse }
    try await webSocket.send(.string(text))
  }

  private func nextCommandId() -> Int {
    let id = nextId
    nextId += 1
    return id
  }

  private func failPendingCommand(id: Int, error: Error) async {
    guard let continuation = pendingCommands.removeValue(forKey: id) else { return }
    continuation.resume(throwing: error)
  }

  private func failAll(_ error: Error) async {
    frameContinuation?.finish(throwing: error)
    frameContinuation = nil
    for continuation in pendingCommands.values {
      continuation.resume(throwing: error)
    }
    pendingCommands.removeAll()
    await close()
  }

  private static func responseId(from text: String) -> Int? {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return json["id"] as? Int
  }

  private static func protocolErrorMessage(from text: String) -> String? {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = json["error"] as? [String: Any]
    else {
      return nil
    }
    return error["message"] as? String ?? "Unknown CDP error"
  }
}

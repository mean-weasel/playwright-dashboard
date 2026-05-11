import Foundation

actor CDPTargetMonitor {
  private let port: Int
  private let requestTimeout: Duration
  private let session: URLSession

  init(port: Int, requestTimeout: Duration = .seconds(3)) {
    self.port = port
    self.requestTimeout = requestTimeout
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout.timeInterval
    configuration.timeoutIntervalForResource = requestTimeout.timeInterval
    self.session = URLSession(configuration: configuration)
  }

  func targetUpdates() -> AsyncThrowingStream<[CDPPageTarget], Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await self.runTargetDiscovery(continuation: continuation)
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func runTargetDiscovery(
    continuation: AsyncThrowingStream<[CDPPageTarget], Error>.Continuation
  ) async throws {
    let wsURL = try await browserWebSocketURL()
    let webSocket = session.webSocketTask(with: wsURL)
    webSocket.resume()
    defer { webSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendWebSocketText(
      try CDPClient.commandString(
        id: 1,
        method: "Target.setDiscoverTargets",
        params: ["discover": true]
      ),
      to: webSocket
    )

    var targetsById: [String: CDPPageTarget] = [:]
    while !Task.isCancelled {
      let message = try await receiveWebSocketMessage(from: webSocket)
      guard case .string(let text) = message else { continue }
      guard let event = Self.parseTargetEvent(text, port: port) else { continue }

      switch event {
      case .upsert(let target):
        targetsById[target.id] = target
      case .remove(let targetId):
        targetsById.removeValue(forKey: targetId)
      }

      let targets = targetsById.values
        .filter(\.isDebuggablePage)
        .sorted {
          $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
      continuation.yield(targets)
    }
  }

  private func browserWebSocketURL() async throws -> URL {
    let url = try CDPClient.cdpHTTPURL(port: port, path: "/json/version")
    let (data, response) = try await withTimeout {
      try await self.session.data(from: url)
    }
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw CDPClient.CDPError.invalidResponse
    }

    let version = try JSONDecoder().decode(BrowserVersion.self, from: data)
    return try CDPClient.validatedWebSocketDebuggerURL(
      version.webSocketDebuggerUrl,
      sourceURL: url
    )
  }

  private func sendWebSocketText(_ text: String, to webSocket: URLSessionWebSocketTask) async throws
  {
    try await withTimeout {
      try await webSocket.send(.string(text))
    }
  }

  private func receiveWebSocketMessage(
    from webSocket: URLSessionWebSocketTask
  ) async throws -> URLSessionWebSocketTask.Message {
    try await webSocket.receive()
  }

  private func withTimeout<T: Sendable>(
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: self.requestTimeout)
        throw CDPClient.CDPError.timeout
      }
      defer { group.cancelAll() }

      guard let result = try await group.next() else {
        throw CDPClient.CDPError.timeout
      }
      return result
    }
  }

  private struct BrowserVersion: Decodable {
    let webSocketDebuggerUrl: String
  }
}

extension CDPTargetMonitor {
  enum TargetEvent: Equatable {
    case upsert(CDPPageTarget)
    case remove(String)
  }

  static func parseTargetEvent(_ text: String, port: Int? = nil) -> TargetEvent? {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let method = json["method"] as? String,
      let params = json["params"] as? [String: Any]
    else {
      return nil
    }

    switch method {
    case "Target.targetCreated", "Target.targetInfoChanged":
      guard let targetInfo = params["targetInfo"] as? [String: Any],
        let target = target(from: targetInfo, port: port)
      else {
        return nil
      }
      return .upsert(target)

    case "Target.targetDestroyed":
      guard let targetId = params["targetId"] as? String else { return nil }
      return .remove(targetId)

    default:
      return nil
    }
  }

  private static func target(from targetInfo: [String: Any], port: Int?) -> CDPPageTarget? {
    guard let id = targetInfo["targetId"] as? String,
      let type = targetInfo["type"] as? String
    else {
      return nil
    }

    return CDPPageTarget(
      id: id,
      type: type,
      url: targetInfo["url"] as? String,
      title: targetInfo["title"] as? String,
      webSocketDebuggerUrl: targetInfo["webSocketDebuggerUrl"] as? String
        ?? fallbackWebSocketDebuggerURL(targetId: id, port: port)
    )
  }

  private static func fallbackWebSocketDebuggerURL(targetId: String, port: Int?) -> String? {
    guard let port, port > 0, !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return "ws://localhost:\(port)/devtools/page/\(targetId)"
  }
}

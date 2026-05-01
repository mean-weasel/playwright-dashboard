import Foundation

struct CDPPageTarget: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let type: String
  let url: String?
  let title: String?
  let webSocketDebuggerUrl: String?

  var displayTitle: String {
    let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedTitle.isEmpty {
      return trimmedTitle
    }

    let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedURL.isEmpty {
      return trimmedURL
    }

    return id
  }

  var isDebuggablePage: Bool {
    type == "page"
      && webSocketDebuggerUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  var isNavigated: Bool {
    guard let value = url?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    return !value.isEmpty && value != "about:blank"
  }

  func devToolsFrontendURL(port: Int) -> URL? {
    let targetId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard port > 0, !targetId.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "http"
    components.host = "localhost"
    components.port = port
    components.path = "/devtools/inspector.html"
    components.queryItems = [
      URLQueryItem(name: "ws", value: "localhost:\(port)/devtools/page/\(targetId)")
    ]
    return components.url
  }
}

enum CDPPageTargetSelection {
  static func pageTargets(from pages: [CDPClient.PageInfo]) -> [CDPPageTarget] {
    pages.map {
      CDPPageTarget(
        id: $0.id,
        type: $0.type,
        url: $0.url,
        title: $0.title,
        webSocketDebuggerUrl: $0.webSocketDebuggerUrl
      )
    }
  }

  static func selectableTargets(from pages: [CDPClient.PageInfo]) -> [CDPPageTarget] {
    pageTargets(from: pages).filter(\.isDebuggablePage)
  }

  static func selectedTarget(
    from pages: [CDPClient.PageInfo],
    preferredTargetId: String?
  ) -> CDPPageTarget? {
    selectedTarget(from: selectableTargets(from: pages), preferredTargetId: preferredTargetId)
  }

  static func selectedTarget(
    from targets: [CDPPageTarget],
    preferredTargetId: String?
  ) -> CDPPageTarget? {
    let debuggableTargets = targets.filter(\.isDebuggablePage)

    if let preferredTargetId,
      let selected = debuggableTargets.first(where: { $0.id == preferredTargetId })
    {
      return selected
    }

    return debuggableTargets.first(where: \.isNavigated) ?? debuggableTargets.first
  }

  static func resolvedSelectedTargetId(
    currentSelectedTargetId: String?,
    targets: [CDPPageTarget]
  ) -> String? {
    selectedTarget(from: targets, preferredTargetId: currentSelectedTargetId)?.id
  }
}

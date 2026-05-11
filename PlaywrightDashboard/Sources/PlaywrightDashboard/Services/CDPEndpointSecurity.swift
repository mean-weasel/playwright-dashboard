import Foundation

extension CDPClient {
  static func cdpHTTPURL(port: Int, path: String) throws -> URL {
    guard (1...65_535).contains(port) else {
      throw CDPError.invalidResponse
    }

    var components = URLComponents()
    components.scheme = "http"
    components.host = "localhost"
    components.port = port
    components.path = path

    guard let url = components.url, isLoopbackOrLocalhost(url.host) else {
      throw CDPError.invalidResponse
    }
    return url
  }

  static func validatedWebSocketDebuggerURL(
    _ rawURL: String?,
    sourceURL: URL
  ) throws -> URL {
    guard
      let value = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty,
      let url = URL(string: value),
      let scheme = url.scheme?.lowercased(),
      scheme == "ws" || scheme == "wss",
      let host = url.host,
      isAllowedDebuggerHost(host, sourceHost: sourceURL.host)
    else {
      throw CDPError.invalidResponse
    }
    return url
  }

  static func isAllowedDebuggerHost(_ host: String, sourceHost: String?) -> Bool {
    if isSameHost(host, sourceHost) {
      return true
    }
    return isLoopbackOrLocalhost(host)
  }

  private static func isSameHost(_ host: String, _ otherHost: String?) -> Bool {
    guard let otherHost else { return false }
    return normalizedHost(host) == normalizedHost(otherHost)
  }

  private static func isLoopbackOrLocalhost(_ host: String?) -> Bool {
    guard let host else { return false }
    let normalized = normalizedHost(host)
    return normalized == "localhost"
      || normalized == "::1"
      || normalized == "0:0:0:0:0:0:0:1"
      || isIPv4LoopbackLiteral(normalized)
  }

  private static func normalizedHost(_ host: String) -> String {
    host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func isIPv4LoopbackLiteral(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }

    var octets: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part),
        (0...255).contains(value)
      else {
        return false
      }
      octets.append(value)
    }

    return octets.first == 127
  }
}

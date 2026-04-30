import Foundation

@MainActor
extension AppState {
  @discardableResult
  func openCurrentURL(_ session: SessionRecord) -> Bool {
    guard let urlString = session.lastURL, !urlString.isEmpty else {
      lastOpenURLError = "No page URL is available."
      return false
    }
    guard let url = URL(string: urlString),
      ["http", "https"].contains(url.scheme?.lowercased())
    else {
      lastOpenURLError = "Only HTTP and HTTPS URLs can be opened."
      return false
    }
    return openExternalURL(url)
  }

  @discardableResult
  func openCDPInspector(_ session: SessionRecord) -> Bool {
    guard session.cdpPort > 0,
      let url = URL(string: "http://localhost:\(session.cdpPort)")
    else {
      lastOpenURLError = "No CDP inspector URL is available."
      return false
    }
    return openExternalURL(url)
  }

  func dismissOpenURLError() {
    lastOpenURLError = nil
  }

  private func openExternalURL(_ url: URL) -> Bool {
    guard urlOpener(url) else {
      lastOpenURLError = "Could not open \(url.absoluteString)."
      return false
    }
    lastOpenURLError = nil
    return true
  }
}

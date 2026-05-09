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
    guard !isSafeMode else {
      lastOpenURLError = "Safe mode is enabled. CDP inspector access is disabled."
      return false
    }

    guard session.cdpPort > 0 else {
      lastOpenURLError = "No CDP inspector URL is available."
      return false
    }

    let url =
      session.selectedPageTarget?.devToolsFrontendURL(port: session.cdpPort)
      ?? URL(string: "http://localhost:\(session.cdpPort)")

    guard let url else {
      lastOpenURLError = "No CDP inspector URL is available."
      return false
    }

    return openExternalURL(url)
  }

  @discardableResult
  func openRecordingDirectory(_ url: URL) -> Bool {
    guard url.isFileURL else {
      lastOpenURLError = "Recording location is not a local file URL."
      return false
    }
    return openExternalURL(url)
  }

  @discardableResult
  func openLatestRelease() -> Bool {
    guard let url = URL(string: "https://github.com/neonwatty/playwright-dashboard/releases/latest")
    else {
      lastOpenURLError = "Latest release URL is invalid."
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

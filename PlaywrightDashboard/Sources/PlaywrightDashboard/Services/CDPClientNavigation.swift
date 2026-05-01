import Foundation

extension CDPClient {
  @discardableResult
  func navigate(to rawURL: String, targetId: String? = nil) async throws -> String {
    let normalizedURL = try Self.normalizedNavigationURLString(rawURL)
    let response = try await sendCommandReturningResponse(
      method: "Page.navigate",
      params: Self.pageNavigateParams(url: normalizedURL),
      targetId: targetId
    )
    if let errorText = Self.pageNavigateErrorText(from: response) {
      throw NavigationError.navigationFailed(errorText)
    }
    return normalizedURL
  }
}

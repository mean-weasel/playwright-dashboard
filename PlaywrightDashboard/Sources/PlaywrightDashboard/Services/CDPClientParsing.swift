import Foundation

extension CDPClient {
  static func parseScreenshotResponse(
    _ text: String,
    expectedId: Int,
    page: PageInfo
  ) throws -> ScreenshotResult? {
    try parseScreenshotResponse(
      text,
      expectedId: expectedId,
      pageTarget: CDPPageTarget(
        id: page.id,
        type: page.type,
        url: page.url,
        title: page.title,
        webSocketDebuggerUrl: page.webSocketDebuggerUrl
      ),
      pageTargets: CDPPageTargetSelection.selectableTargets(from: [page])
    )
  }

  static func parseScreenshotResponse(
    _ text: String,
    expectedId: Int,
    pageTarget: CDPPageTarget,
    pageTargets: [CDPPageTarget]
  ) throws -> ScreenshotResult? {
    guard let responseData = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let responseId = json["id"] as? Int,
      responseId == expectedId
    else {
      return nil
    }

    if let error = json["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown CDP error"
      throw CDPError.protocolError(message)
    }

    guard let result = json["result"] as? [String: Any],
      let base64String = result["data"] as? String,
      let jpeg = Data(base64Encoded: base64String)
    else {
      throw CDPError.invalidResponse
    }

    return ScreenshotResult(
      jpeg: jpeg,
      url: pageTarget.url,
      title: pageTarget.title,
      targetId: pageTarget.id,
      pageTargets: pageTargets
    )
  }
}

import Darwin
import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("CDPClient")
struct CDPClientTests {

  @Test("parseScreenshotResponse returns result for matching response")
  func parseScreenshotResponseSuccess() throws {
    let page = makePage(url: "https://example.com", title: "Example")
    let jpeg = Data([0x01, 0x02, 0x03])
    let response = """
      {"id":7,"result":{"data":"\(jpeg.base64EncodedString())"}}
      """

    let result = try CDPClient.parseScreenshotResponse(response, expectedId: 7, page: page)

    #expect(result?.jpeg == jpeg)
    #expect(result?.url == "https://example.com")
    #expect(result?.title == "Example")
  }

  @Test("parseScreenshotResponse skips events and other command responses")
  func parseScreenshotResponseSkipsUnrelatedMessages() throws {
    let page = makePage()

    let event = try CDPClient.parseScreenshotResponse(
      #"{"method":"Page.loadEventFired","params":{}}"#, expectedId: 7, page: page)
    let otherResponse = try CDPClient.parseScreenshotResponse(
      #"{"id":8,"result":{"data":"AQID"}}"#, expectedId: 7, page: page)

    #expect(event == nil)
    #expect(otherResponse == nil)
  }

  @Test("parseScreenshotResponse throws protocol errors")
  func parseScreenshotResponseProtocolError() throws {
    let page = makePage()

    do {
      _ = try CDPClient.parseScreenshotResponse(
        #"{"id":7,"error":{"message":"Browser failed"}}"#, expectedId: 7, page: page)
      Issue.record("Expected parseScreenshotResponse to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "CDP error: Browser failed")
    }
  }

  @Test("parseScreenshotResponse throws for malformed matching responses")
  func parseScreenshotResponseInvalidResponse() throws {
    let page = makePage()

    do {
      _ = try CDPClient.parseScreenshotResponse(
        #"{"id":7,"result":{}}"#, expectedId: 7, page: page)
      Issue.record("Expected parseScreenshotResponse to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "Invalid screenshot response from CDP")
    }
  }

  @Test("pageForScreenshot prefers a navigated page")
  func pageForScreenshotPrefersNavigatedPage() {
    let pages = [
      makePage(id: "blank", url: "about:blank"),
      makePage(id: "empty", url: ""),
      makePage(id: "app", url: "http://localhost:3000"),
    ]

    #expect(CDPClient.pageForScreenshot(from: pages)?.id == "app")
  }

  @Test("pageForScreenshot falls back to the first page")
  func pageForScreenshotFallsBackToFirstPage() {
    let pages = [
      makePage(id: "blank", url: "about:blank"),
      makePage(id: "empty", url: ""),
    ]

    #expect(CDPClient.pageForScreenshot(from: pages)?.id == "blank")
  }

  @Test("pageForScreenshot ignores non-page targets")
  func pageForScreenshotIgnoresNonPageTargets() {
    let pages = [
      makePage(id: "service-worker", type: "service_worker", url: "http://localhost/worker.js"),
      makePage(id: "app", type: "page", url: "http://localhost:3000"),
    ]

    #expect(CDPClient.pageForScreenshot(from: pages)?.id == "app")
  }

  @Test("mouse event params build CDP click payloads")
  func mouseEventParams() {
    let params = CDPClient.mouseEventParams(
      type: "mousePressed", x: 12.5, y: 30, button: "left", clickCount: 1)

    #expect(params["type"] as? String == "mousePressed")
    #expect(params["x"] as? Double == 12.5)
    #expect(params["y"] as? Double == 30)
    #expect(params["button"] as? String == "left")
    #expect(params["clickCount"] as? Int == 1)
  }

  @Test("mouse wheel params build CDP scroll payloads")
  func mouseWheelParams() {
    let params = CDPClient.mouseWheelParams(x: 100, y: 200, deltaX: 0, deltaY: -40)

    #expect(params["type"] as? String == "mouseWheel")
    #expect(params["x"] as? Double == 100)
    #expect(params["y"] as? Double == 200)
    #expect(params["button"] as? String == "none")
    #expect(params["deltaX"] as? Double == 0)
    #expect(params["deltaY"] as? Double == -40)
  }

  @Test("commandString serializes command id method and params")
  func commandString() throws {
    let text = try CDPClient.commandString(
      id: 3,
      method: "Input.dispatchMouseEvent",
      params: CDPClient.mouseEventParams(
        type: "mouseReleased", x: 12, y: 34, button: "left", clickCount: 1)
    )

    #expect(text.contains(#""id":3"#))
    #expect(text.contains(#""method":"Input.dispatchMouseEvent""#))
    #expect(text.contains(#""type":"mouseReleased""#))
  }

  @Test("isCommandResponse skips events and throws protocol errors")
  func isCommandResponse() throws {
    #expect(try CDPClient.isCommandResponse(#"{"method":"Page.event"}"#, expectedId: 3) == false)
    #expect(try CDPClient.isCommandResponse(#"{"id":3,"result":{}}"#, expectedId: 3))

    do {
      _ = try CDPClient.isCommandResponse(
        #"{"id":3,"error":{"message":"Bad input"}}"#, expectedId: 3)
      Issue.record("Expected command response parsing to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "CDP error: Bad input")
    }
  }

  @Test("listPages times out when CDP HTTP endpoint accepts but does not respond")
  func listPagesTimeout() async throws {
    let server = try HangingHTTPServer()
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .milliseconds(250))
    let startedAt = Date()

    do {
      _ = try await client.listPages()
      Issue.record("Expected listPages to throw")
    } catch {
      #expect(Date().timeIntervalSince(startedAt) < 2)
    }
  }

  private func makePage(
    id: String = "page-1",
    type: String = "page",
    url: String? = "about:blank",
    title: String? = nil
  ) -> CDPClient.PageInfo {
    CDPClient.PageInfo(
      id: id,
      type: type,
      url: url,
      title: title,
      webSocketDebuggerUrl: "ws://localhost/devtools/page/\(id)"
    )
  }

  private final class HangingHTTPServer: @unchecked Sendable {
    private let socketFD: Int32
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init() throws {
      socketFD = socket(AF_INET, SOCK_STREAM, 0)
      guard socketFD >= 0 else { throw POSIXError(.EIO) }

      var reuse: Int32 = 1
      setsockopt(
        socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = in_port_t(0).bigEndian
      address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
          bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }
      guard listen(socketFD, 1) == 0 else { throw POSIXError(.EIO) }

      var boundAddress = sockaddr_in()
      var length = socklen_t(MemoryLayout<sockaddr_in>.size)
      let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
          getsockname(socketFD, sockaddrPointer, &length)
        }
      }
      guard nameResult == 0 else { throw POSIXError(.EIO) }
      port = Int(in_port_t(bigEndian: boundAddress.sin_port))
    }

    func start() throws {
      let socketFD = socketFD
      acceptThread = Thread {
        let clientFD = accept(socketFD, nil, nil)
        if clientFD >= 0 {
          Thread.sleep(forTimeInterval: 10)
          close(clientFD)
        }
      }
      acceptThread?.start()
    }

    func stop() {
      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    deinit {
      stop()
    }
  }
}

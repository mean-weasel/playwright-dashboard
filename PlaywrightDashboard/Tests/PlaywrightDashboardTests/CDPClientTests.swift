import CryptoKit
import Darwin
import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("CDPClient", .serialized)
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

  @Test("pageForScreenshot ignores page targets without websocket URLs")
  func pageForScreenshotRequiresWebSocketURL() {
    let pages = [
      makePage(id: "missing-ws", url: "http://localhost:3000", hasWebSocketDebuggerUrl: false),
      makePage(id: "blank-ws", url: "http://localhost:3001", webSocketDebuggerUrl: "  "),
      makePage(id: "app", url: "http://localhost:3002"),
    ]

    #expect(CDPClient.pageForScreenshot(from: pages)?.id == "app")
  }

  @Test("pageForScreenshot returns nil when no debuggable page exists")
  func pageForScreenshotReturnsNilWithoutDebuggablePage() {
    let pages = [
      makePage(id: "service-worker", type: "service_worker", url: "http://localhost/worker.js"),
      makePage(id: "missing-ws", url: "http://localhost:3000", hasWebSocketDebuggerUrl: false),
    ]

    #expect(CDPClient.pageForScreenshot(from: pages) == nil)
  }

  @Test("target selection honors preferred debuggable target")
  func targetSelectionHonorsPreferredTarget() {
    let pages = [
      makePage(id: "first", url: "http://localhost:3000", title: "First"),
      makePage(id: "second", url: "about:blank", title: "Second"),
    ]

    let selected = CDPPageTargetSelection.selectedTarget(
      from: pages,
      preferredTargetId: "second"
    )

    #expect(selected?.id == "second")
  }

  @Test("target selection falls back when preferred target disappears")
  func targetSelectionFallsBackWhenPreferredTargetDisappears() {
    let pages = [
      makePage(id: "blank", url: "about:blank"),
      makePage(id: "app", url: "http://localhost:3000"),
    ]

    let selected = CDPPageTargetSelection.selectedTarget(
      from: pages,
      preferredTargetId: "missing"
    )

    #expect(selected?.id == "app")
  }

  @Test("target selection ignores preferred non-debuggable target")
  func targetSelectionIgnoresPreferredNonDebuggableTarget() {
    let pages = [
      makePage(
        id: "worker",
        type: "service_worker",
        url: "http://localhost/worker.js",
        hasWebSocketDebuggerUrl: true
      ),
      makePage(id: "app", url: "http://localhost:3000"),
    ]

    let selected = CDPPageTargetSelection.selectedTarget(
      from: pages,
      preferredTargetId: "worker"
    )

    #expect(selected?.id == "app")
  }

  @Test("target monitor parses target lifecycle events")
  func targetMonitorParsesTargetLifecycleEvents() throws {
    let created = CDPTargetMonitor.parseTargetEvent(
      """
      {"method":"Target.targetCreated","params":{"targetInfo":{"targetId":"page-1","type":"page","title":"App","url":"http://localhost:3000"}}}
      """,
      port: 9333
    )
    let changed = CDPTargetMonitor.parseTargetEvent(
      """
      {"method":"Target.targetInfoChanged","params":{"targetInfo":{"targetId":"page-1","type":"page","title":"Renamed","url":"http://localhost:3001","webSocketDebuggerUrl":"ws://localhost:9333/devtools/page/page-1"}}}
      """
    )
    let destroyed = CDPTargetMonitor.parseTargetEvent(
      #"{"method":"Target.targetDestroyed","params":{"targetId":"page-1"}}"#
    )

    guard case .upsert(let createdTarget) = created else {
      Issue.record("Expected targetCreated upsert")
      return
    }
    #expect(createdTarget.id == "page-1")
    #expect(createdTarget.isDebuggablePage)
    #expect(createdTarget.webSocketDebuggerUrl == "ws://localhost:9333/devtools/page/page-1")

    guard case .upsert(let changedTarget) = changed else {
      Issue.record("Expected targetInfoChanged upsert")
      return
    }
    #expect(changedTarget.title == "Renamed")

    #expect(destroyed == .remove("page-1"))
    #expect(CDPTargetMonitor.parseTargetEvent(#"{"id":1,"result":{}}"#) == nil)
  }

  @Test("target monitor discovers targets from browser websocket")
  func targetMonitorDiscoversTargetsFromBrowserWebSocket() async throws {
    let server = try FakeBrowserTargetServer()
    try server.start()
    defer { server.stop() }

    let monitor = CDPTargetMonitor(port: server.port, requestTimeout: .seconds(2))
    var updates = await monitor.targetUpdates().makeAsyncIterator()

    guard let created = try await updates.next() else {
      Issue.record("Expected initial target update")
      return
    }
    #expect(created.map(\.id) == ["page-1"])
    #expect(created.first?.title == "Fake App")
    #expect(
      created.first?.webSocketDebuggerUrl == "ws://localhost:\(server.port)/devtools/page/page-1"
    )

    guard let changed = try await updates.next() else {
      Issue.record("Expected changed target update")
      return
    }
    #expect(changed.map(\.id) == ["page-1"])
    #expect(changed.first?.title == "Renamed App")
    #expect(changed.first?.url == "http://localhost:3001")

    guard let destroyed = try await updates.next() else {
      Issue.record("Expected destroyed target update")
      return
    }
    #expect(destroyed.isEmpty)
    #expect(
      server.receivedCommands().contains { $0.contains(#""method":"Target.setDiscoverTargets""#) }
    )
  }

  @Test("target monitor keeps quiet websocket open between target events")
  func targetMonitorKeepsQuietWebSocketOpen() async throws {
    let server = try FakeBrowserTargetServer(eventDelay: 0.25)
    try server.start()
    defer { server.stop() }

    let monitor = CDPTargetMonitor(port: server.port, requestTimeout: .milliseconds(100))
    var updates = await monitor.targetUpdates().makeAsyncIterator()

    guard let created = try await updates.next() else {
      Issue.record("Expected delayed target update")
      return
    }

    #expect(created.map(\.id) == ["page-1"])
    #expect(created.first?.title == "Fake App")
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

  @Test("key event params include text for printable key down")
  func printableKeyEventParams() {
    let input = CDPClient.KeyEventInput(
      key: "a",
      code: "KeyA",
      text: "a",
      nativeVirtualKeyCode: 0,
      modifiers: 0
    )

    let params = CDPClient.keyEventParams(type: "keyDown", input: input, includeText: true)

    #expect(params["type"] as? String == "keyDown")
    #expect(params["key"] as? String == "a")
    #expect(params["code"] as? String == "KeyA")
    #expect(params["text"] as? String == "a")
    #expect(params["unmodifiedText"] as? String == "a")
    #expect(params["nativeVirtualKeyCode"] as? Int == 0)
  }

  @Test("key event params omit text for key up")
  func keyUpEventParamsOmitText() {
    let input = CDPClient.KeyEventInput(
      key: "Enter",
      code: "Enter",
      text: nil,
      nativeVirtualKeyCode: 36,
      modifiers: 8
    )

    let params = CDPClient.keyEventParams(type: "keyUp", input: input, includeText: false)

    #expect(params["type"] as? String == "keyUp")
    #expect(params["key"] as? String == "Enter")
    #expect(params["code"] as? String == "Enter")
    #expect(params["text"] == nil)
    #expect(params["modifiers"] as? Int == 8)
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

  @Test("normalizedNavigationURLString accepts HTTP HTTPS and bare hosts")
  func normalizedNavigationURLStringAcceptsSupportedURLs() throws {
    #expect(
      try CDPClient.normalizedNavigationURLString("https://example.com/path?q=1")
        == "https://example.com/path?q=1")
    #expect(
      try CDPClient.normalizedNavigationURLString("  HTTP://example.com/a b  ")
        == "http://example.com/a%20b")
    #expect(
      try CDPClient.normalizedNavigationURLString("example.com/app")
        == "https://example.com/app")
    #expect(
      try CDPClient.normalizedNavigationURLString("localhost:3000")
        == "https://localhost:3000")
  }

  @Test("normalizedNavigationURLString rejects empty invalid and unsupported URLs")
  func normalizedNavigationURLStringRejectsInvalidURLs() {
    expectNavigationError(.emptyURL) {
      try CDPClient.normalizedNavigationURLString("   ")
    }
    expectNavigationError(.unsupportedScheme("file")) {
      try CDPClient.normalizedNavigationURLString("file:///tmp/index.html")
    }
    expectNavigationError(.unsupportedScheme("ftp")) {
      try CDPClient.normalizedNavigationURLString("ftp://example.com")
    }
    expectNavigationError(.invalidURL) {
      try CDPClient.normalizedNavigationURLString("https:///missing-host")
    }
  }

  @Test("pageNavigateParams build Page.navigate command payload")
  func pageNavigateParamsBuildCommandPayload() throws {
    let normalizedURL = try CDPClient.normalizedNavigationURLString("example.com/dashboard")
    let text = try CDPClient.commandString(
      id: 4,
      method: "Page.navigate",
      params: CDPClient.pageNavigateParams(url: normalizedURL)
    )

    #expect(text.contains(#""id":4"#))
    #expect(text.contains(#""method":"Page.navigate""#))
    #expect(text.contains(#""url":"https:\/\/example.com\/dashboard""#))
  }

  @Test("pageNavigateErrorText extracts CDP navigation errors")
  func pageNavigateErrorText() {
    #expect(
      CDPClient.pageNavigateErrorText(
        from: #"{"id":4,"result":{"frameId":"A","errorText":"net::ERR_NAME_NOT_RESOLVED"}}"#)
        == "net::ERR_NAME_NOT_RESOLVED")
    #expect(CDPClient.pageNavigateErrorText(from: #"{"id":4,"result":{"frameId":"A"}}"#) == nil)
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

  private func expectNavigationError(
    _ expected: CDPClient.NavigationError,
    operation: () throws -> String
  ) {
    do {
      _ = try operation()
      Issue.record("Expected navigation normalization to throw \(expected)")
    } catch let error as CDPClient.NavigationError {
      #expect(error == expected)
    } catch {
      Issue.record("Expected navigation error, got \(error)")
    }
  }

  @Test("parseScreencastFrame returns frame for CDP screencast event")
  func parseScreencastFrameSuccess() throws {
    let jpeg = Data([0x05, 0x06, 0x07])
    let event = """
      {"method":"Page.screencastFrame","params":{"sessionId":42,"data":"\(jpeg.base64EncodedString())","metadata":{"timestamp":1}}}
      """

    let frame = try CDPClient.parseScreencastFrame(event)

    #expect(frame?.jpeg == jpeg)
    #expect(frame?.sessionId == 42)
  }

  @Test("parseScreencastFrame skips unrelated messages")
  func parseScreencastFrameSkipsUnrelatedMessages() throws {
    let response = try CDPClient.parseScreencastFrame(#"{"id":3,"result":{}}"#)
    let event = try CDPClient.parseScreencastFrame(#"{"method":"Runtime.consoleAPICalled"}"#)

    #expect(response == nil)
    #expect(event == nil)
  }

  @Test("parseScreencastFrame throws protocol errors")
  func parseScreencastFrameProtocolError() throws {
    do {
      _ = try CDPClient.parseScreencastFrame(
        #"{"id":3,"error":{"message":"Screencast failed"}}"#)
      Issue.record("Expected parseScreencastFrame to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "CDP error: Screencast failed")
    }
  }

  @Test("screencastStartParams clamps quality")
  func screencastStartParamsClampsQuality() {
    let params = CDPClient.screencastStartParams(quality: 500)

    #expect(params["format"] as? String == "jpeg")
    #expect(params["quality"] as? Int == 100)
    #expect(params["everyNthFrame"] as? Int == 1)
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

  @Test("listPages rejects non-success HTTP responses")
  func listPagesRejectsHTTPError() async throws {
    let server = try FixedHTTPServer(
      response:
        "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))

    do {
      _ = try await client.listPages()
      Issue.record("Expected listPages to reject non-2xx response")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "Invalid screenshot response from CDP")
    }
  }

  @Test("captureScreenshot skips noisy websocket events until matching response")
  func captureScreenshotSkipsNoisyEvents() async throws {
    let jpeg = Data([0x01, 0x02, 0x03, 0x04])
    let server = try FakeCDPServer(
      eventsBeforeResponse: 12,
      screenshotData: jpeg
    )
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))
    let result = try await client.captureScreenshot(quality: 20)

    #expect(result.jpeg == jpeg)
    #expect(result.url == "http://localhost:3000")
    #expect(result.title == "Fake App")
  }

  @Test("screencastFrames starts stream and acknowledges frames")
  func screencastFramesStartsAndAcknowledgesFrames() async throws {
    let jpeg = Data([0x09, 0x08, 0x07, 0x06])
    let server = try FakeCDPScreencastServer(frameData: jpeg)
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))
    let stream = await client.screencastFrames(quality: 35)
    var iterator = stream.makeAsyncIterator()

    let frame = try await iterator.next()

    #expect(frame?.jpeg == jpeg)
    #expect(frame?.sessionId == 77)
    try await Task.sleep(for: .milliseconds(50))
    let commands = server.receivedCommands()
    #expect(commands.contains { $0.contains(#""method":"Page.startScreencast""#) })
    #expect(commands.contains { $0.contains(#""quality":35"#) })
    #expect(commands.contains { $0.contains(#""method":"Page.screencastFrameAck""#) })
    #expect(commands.contains { $0.contains(#""sessionId":77"#) })
  }

  @Test("page connection sends input on the screencast websocket")
  func pageConnectionSendsInputOnScreencastWebSocket() async throws {
    let server = try FakeCDPScreencastServer(
      frameData: Data([0x01, 0x02]),
      expectedInputCommandCount: 2
    )
    try server.start()
    defer { server.stop() }

    let connection = CDPPageConnection(port: server.port, requestTimeout: .seconds(2))
    let stream = try await connection.startScreencast(quality: 40)
    var iterator = stream.makeAsyncIterator()
    _ = try await iterator.next()

    try await connection.dispatchMouseClick(x: 14, y: 28)
    try await Task.sleep(for: .milliseconds(50))
    await connection.close()

    let commands = server.receivedCommands()
    #expect(commands.contains { $0.contains(#""method":"Page.startScreencast""#) })
    #expect(commands.contains { $0.contains(#""method":"Page.screencastFrameAck""#) })
    #expect(commands.contains { $0.contains(#""type":"mousePressed""#) })
    #expect(commands.contains { $0.contains(#""type":"mouseReleased""#) })
    #expect(commands.contains { $0.contains(#""x":14"#) })
    #expect(commands.contains { $0.contains(#""y":28"#) })
  }

  @Test("page connection surfaces start screencast protocol errors")
  func pageConnectionSurfacesStartScreencastProtocolErrors() async throws {
    let server = try FakeCDPScreencastServer(
      frameData: Data([0x01]),
      startErrorMessage: "Screencast unsupported"
    )
    try server.start()
    defer { server.stop() }

    let connection = CDPPageConnection(port: server.port, requestTimeout: .seconds(2))

    do {
      _ = try await connection.startScreencast(quality: 40)
      Issue.record("Expected startScreencast to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "CDP error: Screencast unsupported")
    }

    let commands = server.receivedCommands()
    #expect(commands.contains { $0.contains(#""method":"Page.startScreencast""#) })
    await connection.close()
  }

  @Test("dispatchKeyPress sends key down and key up commands")
  func dispatchKeyPressSendsCommands() async throws {
    let server = try FakeCDPCommandServer(expectedCommandCount: 2)
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))
    try await client.dispatchKeyPress(
      CDPClient.KeyEventInput(
        key: "a",
        code: "KeyA",
        text: "a",
        nativeVirtualKeyCode: 0,
        modifiers: 0
      )
    )

    let commands = server.receivedCommands()
    #expect(commands.count == 2)
    #expect(commands[0].contains(#""method":"Input.dispatchKeyEvent""#))
    #expect(commands[0].contains(#""type":"keyDown""#))
    #expect(commands[0].contains(#""text":"a""#))
    #expect(commands[1].contains(#""method":"Input.dispatchKeyEvent""#))
    #expect(commands[1].contains(#""type":"keyUp""#))
  }

  @Test("dispatchMouseClick sends pressed and released commands")
  func dispatchMouseClickSendsCommands() async throws {
    let server = try FakeCDPCommandServer(expectedCommandCount: 2)
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))
    try await client.dispatchMouseClick(x: 12, y: 34)

    let commands = server.receivedCommands()
    #expect(commands.count == 2)
    #expect(commands[0].contains(#""method":"Input.dispatchMouseEvent""#))
    #expect(commands[0].contains(#""type":"mousePressed""#))
    #expect(commands[0].contains(#""x":12"#))
    #expect(commands[0].contains(#""y":34"#))
    #expect(commands[1].contains(#""method":"Input.dispatchMouseEvent""#))
    #expect(commands[1].contains(#""type":"mouseReleased""#))
  }

  @Test("dispatchMouseWheel sends wheel command")
  func dispatchMouseWheelSendsCommand() async throws {
    let server = try FakeCDPCommandServer(expectedCommandCount: 1)
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))
    try await client.dispatchMouseWheel(x: 10, y: 20, deltaX: 1, deltaY: -8)

    let commands = server.receivedCommands()
    #expect(commands.count == 1)
    #expect(commands[0].contains(#""method":"Input.dispatchMouseEvent""#))
    #expect(commands[0].contains(#""type":"mouseWheel""#))
    #expect(commands[0].contains(#""deltaX":1"#))
    #expect(commands[0].contains(#""deltaY":-8"#))
  }

  @Test("dispatch commands surface CDP protocol errors")
  func dispatchCommandSurfacesProtocolError() async throws {
    let server = try FakeCDPCommandServer(
      expectedCommandCount: 1,
      errorOnCommandIndex: 0,
      errorMessage: "Target closed"
    )
    try server.start()
    defer { server.stop() }

    let client = CDPClient(port: server.port, requestTimeout: .seconds(2))

    do {
      try await client.dispatchMouseWheel(x: 10, y: 20, deltaX: 0, deltaY: 4)
      Issue.record("Expected dispatchMouseWheel to throw")
    } catch let error as CDPClient.CDPError {
      #expect(error.errorDescription == "CDP error: Target closed")
    }
  }

  private func makePage(
    id: String = "page-1",
    type: String = "page",
    url: String? = "about:blank",
    title: String? = nil,
    hasWebSocketDebuggerUrl: Bool = true,
    webSocketDebuggerUrl: String? = nil
  ) -> CDPClient.PageInfo {
    CDPClient.PageInfo(
      id: id,
      type: type,
      url: url,
      title: title,
      webSocketDebuggerUrl: hasWebSocketDebuggerUrl
        ? (webSocketDebuggerUrl ?? "ws://localhost/devtools/page/\(id)") : nil
    )
  }

  private final class HangingHTTPServer: @unchecked Sendable {
    private let socketFD: Int32
    private let stopLock = NSLock()
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init() throws {
      signal(SIGPIPE, SIG_IGN)
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
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    deinit {
      stop()
    }
  }

  private final class FixedHTTPServer: @unchecked Sendable {
    private let socketFD: Int32
    private let response: String
    private let stopLock = NSLock()
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init(response: String) throws {
      signal(SIGPIPE, SIG_IGN)
      self.response = response
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
      let response = response
      acceptThread = Thread {
        let clientFD = accept(socketFD, nil, nil)
        if clientFD >= 0 {
          _ = Self.readHTTPRequest(from: clientFD)
          let bytes = Array(response.utf8)
          _ = bytes.withUnsafeBufferPointer { buffer in
            send(clientFD, buffer.baseAddress, buffer.count, 0)
          }
          close(clientFD)
        }
      }
      acceptThread?.start()
    }

    func stop() {
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    deinit {
      stop()
    }

    private static func readHTTPRequest(from fd: Int32) -> String {
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else { break }
        data.append(buffer, count: count)
        if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
      }
      return String(data: data, encoding: .utf8) ?? ""
    }
  }

  private final class FakeCDPServer: @unchecked Sendable {
    private let socketFD: Int32
    private let eventsBeforeResponse: Int
    private let screenshotData: Data
    private let stopLock = NSLock()
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init(eventsBeforeResponse: Int, screenshotData: Data) throws {
      signal(SIGPIPE, SIG_IGN)
      self.eventsBeforeResponse = eventsBeforeResponse
      self.screenshotData = screenshotData
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
      guard listen(socketFD, 2) == 0 else { throw POSIXError(.EIO) }

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
      let port = port
      let eventsBeforeResponse = eventsBeforeResponse
      let screenshotData = screenshotData
      acceptThread = Thread {
        let listFD = accept(socketFD, nil, nil)
        if listFD >= 0 {
          _ = Self.readHTTPRequest(from: listFD)
          Self.sendHTTPResponse(
            to: listFD,
            body: Self.pageListJSON(port: port)
          )
          close(listFD)
        }

        let webSocketFD = accept(socketFD, nil, nil)
        guard webSocketFD >= 0 else { return }
        defer { close(webSocketFD) }

        let request = Self.readHTTPRequest(from: webSocketFD)
        guard let key = Self.headerValue("Sec-WebSocket-Key", in: request) else { return }
        Self.sendWebSocketHandshake(to: webSocketFD, key: key)
        _ = Self.readWebSocketFrame(from: webSocketFD)

        for index in 0..<eventsBeforeResponse {
          Self.sendWebSocketText(
            #"{"method":"Runtime.consoleAPICalled","params":{"index":\#(index)}}"#,
            to: webSocketFD
          )
        }

        Self.sendWebSocketText(
          #"{"id":1,"result":{"data":"\#(screenshotData.base64EncodedString())"}}"#,
          to: webSocketFD
        )
        Thread.sleep(forTimeInterval: 0.05)
      }
      acceptThread?.start()
    }

    func stop() {
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    deinit {
      stop()
    }

    static func pageListJSON(port: Int) -> String {
      """
      [{"id":"page-1","type":"page","url":"http://localhost:3000","title":"Fake App","webSocketDebuggerUrl":"ws://localhost:\(port)/devtools/page/page-1"}]
      """
    }

    static func sendHTTPResponse(to fd: Int32, body: String) {
      let response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
      sendString(response, to: fd)
    }

    static func sendWebSocketHandshake(to fd: Int32, key: String) {
      let accept = webSocketAccept(for: key)
      let response =
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
      sendString(response, to: fd)
    }

    private static func webSocketAccept(for key: String) -> String {
      let combined = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
      let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
      return Data(digest).base64EncodedString()
    }

    static func sendWebSocketText(_ text: String, to fd: Int32) {
      let payload = Array(text.utf8)
      var frame: [UInt8] = [0x81]
      if payload.count < 126 {
        frame.append(UInt8(payload.count))
      } else {
        frame.append(126)
        frame.append(UInt8((payload.count >> 8) & 0xff))
        frame.append(UInt8(payload.count & 0xff))
      }
      frame.append(contentsOf: payload)
      frame.withUnsafeBufferPointer { buffer in
        _ = send(fd, buffer.baseAddress, buffer.count, 0)
      }
    }

    static func readHTTPRequest(from fd: Int32) -> String {
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else { break }
        data.append(buffer, count: count)
        if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
      }
      return String(data: data, encoding: .utf8) ?? ""
    }

    static func readWebSocketFrame(from fd: Int32) -> Data {
      var header = [UInt8](repeating: 0, count: 2)
      guard recv(fd, &header, 2, MSG_WAITALL) == 2 else { return Data() }

      let masked = (header[1] & 0x80) != 0
      var length = Int(header[1] & 0x7f)
      if length == 126 {
        var extended = [UInt8](repeating: 0, count: 2)
        guard recv(fd, &extended, 2, MSG_WAITALL) == 2 else { return Data() }
        length = (Int(extended[0]) << 8) | Int(extended[1])
      }

      var mask = [UInt8](repeating: 0, count: 4)
      if masked {
        guard recv(fd, &mask, 4, MSG_WAITALL) == 4 else { return Data() }
      }

      var payload = [UInt8](repeating: 0, count: length)
      guard recv(fd, &payload, length, MSG_WAITALL) == length else { return Data() }
      if masked {
        for index in payload.indices {
          payload[index] ^= mask[index % 4]
        }
      }
      return Data(payload)
    }

    static func headerValue(_ name: String, in request: String) -> String? {
      for line in request.components(separatedBy: "\r\n") {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].caseInsensitiveCompare(name) == .orderedSame else {
          continue
        }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return nil
    }

    private static func sendString(_ text: String, to fd: Int32) {
      let bytes = Array(text.utf8)
      bytes.withUnsafeBufferPointer { buffer in
        _ = send(fd, buffer.baseAddress, buffer.count, 0)
      }
    }
  }

  private final class FakeBrowserTargetServer: @unchecked Sendable {
    private let socketFD: Int32
    private let eventDelay: TimeInterval
    private let lock = NSLock()
    private let stopLock = NSLock()
    private var commands: [String] = []
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init(eventDelay: TimeInterval = 0) throws {
      signal(SIGPIPE, SIG_IGN)
      self.eventDelay = eventDelay
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
      guard listen(socketFD, 2) == 0 else { throw POSIXError(.EIO) }

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
      let port = port
      let eventDelay = eventDelay
      acceptThread = Thread { [weak self] in
        guard let self else { return }
        let versionFD = accept(socketFD, nil, nil)
        if versionFD >= 0 {
          _ = FakeCDPServer.readHTTPRequest(from: versionFD)
          FakeCDPServer.sendHTTPResponse(
            to: versionFD,
            body: #"{"webSocketDebuggerUrl":"ws://localhost:\#(port)/devtools/browser/browser-1"}"#
          )
          close(versionFD)
        }

        let webSocketFD = accept(socketFD, nil, nil)
        guard webSocketFD >= 0 else { return }
        defer { close(webSocketFD) }

        let request = FakeCDPServer.readHTTPRequest(from: webSocketFD)
        guard let key = FakeCDPServer.headerValue("Sec-WebSocket-Key", in: request) else {
          return
        }
        FakeCDPServer.sendWebSocketHandshake(to: webSocketFD, key: key)

        let command =
          String(data: FakeCDPServer.readWebSocketFrame(from: webSocketFD), encoding: .utf8) ?? ""
        self.record(command)
        FakeCDPServer.sendWebSocketText(#"{"id":1,"result":{}}"#, to: webSocketFD)
        if eventDelay > 0 {
          Thread.sleep(forTimeInterval: eventDelay)
        }
        FakeCDPServer.sendWebSocketText(
          """
          {"method":"Target.targetCreated","params":{"targetInfo":{"targetId":"page-1","type":"page","title":"Fake App","url":"http://localhost:3000"}}}
          """,
          to: webSocketFD
        )
        FakeCDPServer.sendWebSocketText(
          """
          {"method":"Target.targetInfoChanged","params":{"targetInfo":{"targetId":"page-1","type":"page","title":"Renamed App","url":"http://localhost:3001"}}}
          """,
          to: webSocketFD
        )
        FakeCDPServer.sendWebSocketText(
          #"{"method":"Target.targetDestroyed","params":{"targetId":"page-1"}}"#,
          to: webSocketFD
        )
        Thread.sleep(forTimeInterval: 0.05)
      }
      acceptThread?.start()
    }

    func stop() {
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    func receivedCommands() -> [String] {
      lock.lock()
      defer { lock.unlock() }
      return commands
    }

    deinit {
      stop()
    }

    private func record(_ command: String) {
      lock.lock()
      commands.append(command)
      lock.unlock()
    }
  }

  private final class FakeCDPCommandServer: @unchecked Sendable {
    private let socketFD: Int32
    private let expectedCommandCount: Int
    private let errorOnCommandIndex: Int?
    private let errorMessage: String
    private let lock = NSLock()
    private let stopLock = NSLock()
    private var commands: [String] = []
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init(
      expectedCommandCount: Int,
      errorOnCommandIndex: Int? = nil,
      errorMessage: String = "Protocol failed"
    ) throws {
      signal(SIGPIPE, SIG_IGN)
      self.expectedCommandCount = expectedCommandCount
      self.errorOnCommandIndex = errorOnCommandIndex
      self.errorMessage = errorMessage
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
      guard listen(socketFD, 4) == 0 else { throw POSIXError(.EIO) }

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
      let port = port
      let expectedCommandCount = expectedCommandCount
      let errorOnCommandIndex = errorOnCommandIndex
      let errorMessage = errorMessage
      acceptThread = Thread { [weak self] in
        guard let self else { return }
        let listFD = accept(socketFD, nil, nil)
        if listFD >= 0 {
          _ = FakeCDPServer.readHTTPRequest(from: listFD)
          FakeCDPServer.sendHTTPResponse(to: listFD, body: FakeCDPServer.pageListJSON(port: port))
          close(listFD)
        }

        let webSocketFD = accept(socketFD, nil, nil)
        guard webSocketFD >= 0 else { return }
        defer { close(webSocketFD) }

        let request = FakeCDPServer.readHTTPRequest(from: webSocketFD)
        guard let key = FakeCDPServer.headerValue("Sec-WebSocket-Key", in: request) else {
          return
        }
        FakeCDPServer.sendWebSocketHandshake(to: webSocketFD, key: key)

        for commandIndex in 0..<expectedCommandCount {
          let payload = FakeCDPServer.readWebSocketFrame(from: webSocketFD)
          let command = String(data: payload, encoding: .utf8) ?? ""
          self.record(command)
          let id = Self.commandId(from: command) ?? 0
          if commandIndex == errorOnCommandIndex {
            FakeCDPServer.sendWebSocketText(
              #"{"id":\#(id),"error":{"message":"\#(errorMessage)"}}"#,
              to: webSocketFD
            )
          } else {
            FakeCDPServer.sendWebSocketText(#"{"id":\#(id),"result":{}}"#, to: webSocketFD)
          }
        }
        Thread.sleep(forTimeInterval: 0.02)
      }
      acceptThread?.start()
    }

    func stop() {
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    func receivedCommands() -> [String] {
      lock.lock()
      defer { lock.unlock() }
      return commands
    }

    deinit {
      stop()
    }

    private func record(_ command: String) {
      lock.lock()
      commands.append(command)
      lock.unlock()
    }

    private static func commandId(from command: String) -> Int? {
      guard let data = command.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return nil
      }
      return json["id"] as? Int
    }
  }

  private final class FakeCDPScreencastServer: @unchecked Sendable {
    private let socketFD: Int32
    private let frameData: Data
    private let expectedInputCommandCount: Int
    private let startErrorMessage: String?
    private let lock = NSLock()
    private let stopLock = NSLock()
    private var commands: [String] = []
    private var isStopped = false
    private var acceptThread: Thread?
    private(set) var port: Int = 0

    init(
      frameData: Data,
      expectedInputCommandCount: Int = 0,
      startErrorMessage: String? = nil
    ) throws {
      signal(SIGPIPE, SIG_IGN)
      self.frameData = frameData
      self.expectedInputCommandCount = expectedInputCommandCount
      self.startErrorMessage = startErrorMessage
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
      guard listen(socketFD, 2) == 0 else { throw POSIXError(.EIO) }

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
      let port = port
      let frameData = frameData
      let expectedInputCommandCount = expectedInputCommandCount
      let startErrorMessage = startErrorMessage
      acceptThread = Thread { [weak self] in
        guard let self else { return }
        let listFD = accept(socketFD, nil, nil)
        if listFD >= 0 {
          _ = FakeCDPServer.readHTTPRequest(from: listFD)
          FakeCDPServer.sendHTTPResponse(to: listFD, body: FakeCDPServer.pageListJSON(port: port))
          close(listFD)
        }

        let webSocketFD = accept(socketFD, nil, nil)
        guard webSocketFD >= 0 else { return }
        defer { close(webSocketFD) }

        let request = FakeCDPServer.readHTTPRequest(from: webSocketFD)
        guard let key = FakeCDPServer.headerValue("Sec-WebSocket-Key", in: request) else {
          return
        }
        FakeCDPServer.sendWebSocketHandshake(to: webSocketFD, key: key)

        let startCommand = Self.readCommand(from: webSocketFD)
        self.record(startCommand)
        let startId = Self.commandId(from: startCommand) ?? 1
        if let startErrorMessage {
          FakeCDPServer.sendWebSocketText(
            #"{"id":\#(startId),"error":{"message":"\#(startErrorMessage)"}}"#,
            to: webSocketFD
          )
          Thread.sleep(forTimeInterval: 0.02)
          return
        }
        FakeCDPServer.sendWebSocketText(#"{"id":\#(startId),"result":{}}"#, to: webSocketFD)
        FakeCDPServer.sendWebSocketText(
          #"{"method":"Page.screencastFrame","params":{"sessionId":77,"data":"\#(frameData.base64EncodedString())","metadata":{"timestamp":1}}}"#,
          to: webSocketFD
        )

        let ackCommand = Self.readCommand(from: webSocketFD)
        self.record(ackCommand)

        for _ in 0..<expectedInputCommandCount {
          let inputCommand = Self.readCommand(from: webSocketFD)
          self.record(inputCommand)
          let inputId = Self.commandId(from: inputCommand) ?? 0
          FakeCDPServer.sendWebSocketText(
            #"{"id":\#(inputId),"result":{}}"#,
            to: webSocketFD
          )
        }
        Thread.sleep(forTimeInterval: 0.02)
      }
      acceptThread?.start()
    }

    func stop() {
      stopLock.lock()
      guard !isStopped else {
        stopLock.unlock()
        return
      }
      isStopped = true
      stopLock.unlock()

      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }

    func receivedCommands() -> [String] {
      lock.lock()
      defer { lock.unlock() }
      return commands
    }

    deinit {
      stop()
    }

    private func record(_ command: String) {
      lock.lock()
      commands.append(command)
      lock.unlock()
    }

    private static func readCommand(from fd: Int32) -> String {
      let payload = FakeCDPServer.readWebSocketFrame(from: fd)
      return String(data: payload, encoding: .utf8) ?? ""
    }

    private static func commandId(from command: String) -> Int? {
      guard let data = command.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return nil
      }
      return json["id"] as? Int
    }
  }
}

import Darwin
import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("CDPClient")
struct CDPClientTests {

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

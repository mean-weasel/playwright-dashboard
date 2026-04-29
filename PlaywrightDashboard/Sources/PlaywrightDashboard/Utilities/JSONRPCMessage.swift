import Foundation

struct JSONRPCMessage: Codable, Sendable {
  let jsonrpc: String
  let method: String?
  let id: Int?
}

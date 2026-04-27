import Foundation

// Task 4 implements this
struct JSONRPCMessage: Codable, Sendable {
    let jsonrpc: String
    let method: String?
    let id: Int?
}

import Foundation

/// A consumed rotation is protected at rest and cannot be used until identity verification finishes.
public struct ChatGPTPendingRefresh: Codable, Sendable {
    public let tokens: ChatGPTTokenSet
    public let receivedAt: Date
}

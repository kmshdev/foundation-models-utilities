import Foundation

/// Required conversation history is sent explicitly on every stateless request.
public struct ChatGPTResponsesMessage: Encodable, Sendable, Equatable {
    public enum Role: String, Encodable, Sendable { case developer, user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

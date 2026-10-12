import Foundation

public struct RoomMessage: Identifiable, Codable, Sendable, Equatable {
    public enum Author: String, Codable, Sendable { case user, coordinator }
    public let id: UUID
    public let author: Author
    public let text: String
    public let createdAt: Date
    /// Optional for compatibility with workspaces written before outcome threads.
    public let outcomeID: UUID?
    public init(id: UUID = UUID(), author: Author, text: String, createdAt: Date = .now, outcomeID: UUID? = nil) {
        self.id = id; self.author = author; self.text = text; self.createdAt = createdAt
        self.outcomeID = outcomeID
    }
}

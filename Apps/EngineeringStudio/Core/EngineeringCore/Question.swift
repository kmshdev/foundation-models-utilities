import Foundation

public struct Question: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let prompt: String
    public let options: [String]
    public var answer: String?
    public init(id: UUID = UUID(), prompt: String, options: [String] = [], answer: String? = nil) {
        self.id = id; self.prompt = prompt; self.options = options; self.answer = answer
    }
}

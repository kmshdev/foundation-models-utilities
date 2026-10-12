import Foundation

public struct ExecutionPublicationIdentity: Codable, Sendable, Equatable {
    public let name: String
    public let email: String
    public let date: String
    public init(name: String, email: String, date: String) { self.name = name; self.email = email; self.date = date }
}

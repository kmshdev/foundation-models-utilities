import Foundation

public struct OutcomeSource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case linear }
    public let kind: Kind
    public let id: String
    public let url: URL

    public init(kind: Kind, id: String, url: URL) {
        self.kind = kind; self.id = id; self.url = url
    }

    public func matches(kind: Kind, id: String) -> Bool {
        guard self.kind == kind else { return false }
        if let first = UUID(uuidString: self.id), let second = UUID(uuidString: id) { return first == second }
        return self.id == id
    }
}

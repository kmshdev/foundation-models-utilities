import Foundation

public struct WorkTask: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let owner: Specialty
    public let paths: [String]
    public let acceptance: [String]
    public let dependencies: [String]
    public let handoff: String
    public init(id: String, title: String, owner: Specialty, paths: [String], acceptance: [String], dependencies: [String], handoff: String) {
        self.id = id; self.title = title; self.owner = owner; self.paths = paths
        self.acceptance = acceptance; self.dependencies = dependencies; self.handoff = handoff
    }
}

import Foundation

public struct WorkPlan: Codable, Sendable, Equatable {
    public let summary: String
    public let tasks: [WorkTask]
    public init(summary: String, tasks: [WorkTask]) { self.summary = summary; self.tasks = tasks }
}

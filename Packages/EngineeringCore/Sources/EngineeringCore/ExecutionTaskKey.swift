import Foundation

public struct ExecutionTaskKey: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let outcomeID: UUID
    public let taskID: String
    public var id: String { "\(outcomeID.uuidString)/\(taskID)" }
    public init(outcomeID: UUID, taskID: String) { self.outcomeID = outcomeID; self.taskID = taskID }
}

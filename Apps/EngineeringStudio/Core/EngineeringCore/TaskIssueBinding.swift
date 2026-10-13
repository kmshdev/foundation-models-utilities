import Foundation

/// A durable, client-reserved Linear issue ID for one task within one outcome.
/// A reservation is not evidence that Linear accepted a mutation.
public struct TaskIssueBinding: Identifiable, Codable, Sendable, Equatable {
    public let outcomeID: UUID
    public let taskID: String
    public let issueID: UUID
    public private(set) var identifier: String?
    public private(set) var webURL: URL?
    public private(set) var publishedTask: WorkTask?
    public var id: String { "\(outcomeID.uuidString)/\(taskID)" }

    public init(outcomeID: UUID, taskID: String, issueID: UUID = UUID()) {
        self.outcomeID = outcomeID; self.taskID = taskID; self.issueID = issueID
    }

    mutating func record(identifier: String, webURL: URL, task: WorkTask) {
        self.identifier = identifier; self.webURL = webURL; publishedTask = task
    }
}

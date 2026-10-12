import Foundation

/// Durable delivery and git evidence. Completion describes the observed turn and
/// scope check; acceptance criteria and command results remain available for review.
public struct ExecutionRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case queued, starting, running, verifying, completed, blocked, cancelled, interrupted }
    public let id: UUID
    public let key: ExecutionTaskKey
    public let outcome: String
    public let task: WorkTask
    public var deliveryID: UUID
    public var status: Status
    public var threadID: String?
    public var turnID: String?
    public var worktree: ExecutionWorktree?
    public var receivedHandoffs: [ExecutionTaskKey]
    public var commands: [ExecutionCommandReceipt]
    public var changedPaths: [String]
    public var commitSHA: String?
    public var summary: String
    public var result: ExecutionTaskResult?
    public var blocker: String?
    public var updatedAt: Date
    public init(key: ExecutionTaskKey, outcome: String, task: WorkTask, id: UUID = UUID()) {
        self.id = id; self.key = key; self.outcome = outcome; self.task = task; deliveryID = id; status = .queued
        receivedHandoffs = []; commands = []; changedPaths = []; summary = ""; result = nil; updatedAt = .now
    }
    public var isActive: Bool { [.starting, .running, .verifying].contains(status) }
}

import Foundation

public protocol ExecutionWorktreeManaging: Sendable {
    func prepare(executionID: UUID, dependencyCommits: [String]) async throws -> ExecutionWorktree
    func verifyAndCommit(task: WorkTask, worktree: ExecutionWorktree) async throws -> ExecutionGitReceipt
}

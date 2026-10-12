import Foundation

/// An observed Codex command item, not an inferred test result or test count.
public struct ExecutionCommandReceipt: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let command: String
    public let workingDirectory: String
    public let exitCode: Int?
    public let status: String
    public let output: String
    public init(id: String, command: String, workingDirectory: String, exitCode: Int?, status: String, output: String) {
        self.id = id; self.command = command; self.workingDirectory = workingDirectory
        self.exitCode = exitCode; self.status = status; self.output = output
    }
}

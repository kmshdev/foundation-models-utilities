import Foundation

public enum ExecutionError: Error, LocalizedError, Sendable, Equatable {
    case unavailable(String), notConnected, timedOut(String), transportEnded, malformedMessage
    case rpcRejected(Int), invalidConfiguration(String), scopeViolation([String]), taskChanged
    case dependenciesFailed, commandFailed(String, Int32), persistenceFailed, alreadyRunning
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason), .invalidConfiguration(let reason): reason
        case .notConnected: "Start the developer executor before dispatching a plan."
        case .timedOut(let method): "The developer executor did not respond to \(method)."
        case .transportEnded: "The developer process disconnected. Its worktree and receipts were retained."
        case .malformedMessage: "The developer process returned an invalid or oversized RPC message."
        case .rpcRejected(let code): "The developer process rejected the request (RPC \(code))."
        case .scopeViolation(let paths): "The developer changed files outside its assigned scope: \(paths.joined(separator: ", "))."
        case .taskChanged: "An existing execution has a different task definition. Create a new task ID for changed work."
        case .dependenciesFailed: "A dependency did not complete. Resolve its recorded blocker before continuing."
        case .commandFailed(let name, let code): "\(name) exited with status \(code)."
        case .persistenceFailed: "The execution receipt could not be saved. Dispatch paused to prevent duplicate delivery."
        case .alreadyRunning: "The developer executor is already starting."
        }
    }
}

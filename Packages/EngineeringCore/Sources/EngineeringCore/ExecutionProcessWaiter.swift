import Foundation

#if os(macOS) || os(Linux)
/// Foundation's blocking wait needs its own executor so it can reap the child.
/// Safety: the reference crosses to exactly one waiter after Process.run(); launch
/// configuration is never mutated again. The actor only signals termination.
/// Remove this bridge when Foundation exposes an async, Sendable process lifetime.
final class ExecutionProcessWaiter: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func wait() { process.waitUntilExit() }
}
#endif

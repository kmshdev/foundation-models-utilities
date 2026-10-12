import EngineeringCore
import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

#if os(macOS) || os(Linux)
/// Apple Process owns the child, while this actor owns all RPC IDs and framing.
/// The provider token stays in the process environment and is never an RPC item.
public actor ExecutionCodexProcess: ExecutionRPCTransport {
    private enum Chunk: Sendable { case data(Data), ended }
    private struct Pending {
        let continuation: CheckedContinuation<ExecutionJSON, any Error>
        let timeout: Task<Void, Never>
    }
    private let configuration: ExecutionProcessConfiguration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var reader: Task<Void, Never>?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: Pending] = [:]
    private var observers: [UUID: AsyncStream<ExecutionNotification>.Continuation] = [:]
    private var generation = UUID()
    private let maximumMessageBytes = 4 * 1024 * 1024

    public init(configuration: ExecutionProcessConfiguration) { self.configuration = configuration }

    public func start(accessToken: String?) throws {
        guard process == nil else { throw ExecutionError.alreadyRunning }
        guard configuration.executableURL.isFileURL,
              FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw ExecutionError.unavailable("Choose an installed, executable Codex CLI binary in Developer Runtime settings.")
        }
        if configuration.usesChatGPTPlanProvider {
            guard let accessToken, !accessToken.isEmpty else {
                throw ExecutionError.unavailable("Sign in with ChatGPT before starting developer execution.")
            }
        }
        try FileManager.default.createDirectory(at: configuration.codexHome, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configuration.codexHome.path)
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = configuration.executableURL
        child.arguments = configuration.arguments
        child.currentDirectoryURL = configuration.workingDirectory
        // Keep ordinary runtime paths, never ambient service tokens or keys.
        let allowed = Set(["PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR"])
        var environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        environment["CODEX_HOME"] = configuration.codexHome.path
        if let accessToken { environment["ACCESS_TOKEN"] = accessToken }
        child.environment = environment
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        let currentGeneration = UUID(); generation = currentGeneration
        let chunks = AsyncStream<Chunk>.makeStream()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { chunks.continuation.yield(.ended); chunks.continuation.finish() }
            else { chunks.continuation.yield(.data(data)) }
        }
        // Drain diagnostics without forwarding arbitrary stderr (which can contain credentials).
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        child.terminationHandler = { _ in chunks.continuation.yield(.ended); chunks.continuation.finish() }
        do { try child.run() }
        catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw ExecutionError.unavailable("The selected Codex binary could not launch. Check its architecture and the app's filesystem permissions.")
        }
        process = child; input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading; errorOutput = stderr.fileHandleForReading
        buffer.removeAll(keepingCapacity: true)
        reader = Task { [weak self] in
            for await chunk in chunks.stream { await self?.consume(chunk, generation: currentGeneration) }
        }
    }

    public func request(method: String, params: ExecutionJSON) async throws -> ExecutionJSON {
        guard process?.isRunning == true else { throw ExecutionError.notConnected }
        let id = nextID; nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self, delay = configuration.requestTimeout] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    await self?.reject(id: id, error: ExecutionError.timedOut(method))
                }
                pending[id] = Pending(continuation: continuation, timeout: timeout)
                do { try send(.object(["id": .number(Double(id)), "method": .string(method), "params": params])) }
                catch { reject(id: id, error: error) }
            }
        } onCancel: { [weak self] in Task { await self?.reject(id: id, error: CancellationError()) } }
    }

    public func notify(method: String, params: ExecutionJSON) throws {
        try send(.object(["method": .string(method), "params": params]))
    }

    public func notifications() -> AsyncStream<ExecutionNotification> {
        let id = UUID(), pair = AsyncStream<ExecutionNotification>.makeStream()
        observers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return pair.stream
    }

    public func stop() async {
        let child = process
        generation = UUID()
        output?.readabilityHandler = nil; errorOutput?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); try? errorOutput?.close()
        input = nil; output = nil; errorOutput = nil; process = nil
        reader?.cancel(); reader = nil
        for id in Array(pending.keys) { reject(id: id, error: ExecutionError.transportEnded) }
        guard let child, child.isRunning else { return }
        let waiter = ExecutionProcessWaiter(child)
        let waitTask = Task { @concurrent in waiter.wait() }
        child.terminate()
        // Do not release a worktree for resume merely because a signal was sent.
        // Keep the bounded wait off the caller's UI executor.
        for _ in 0..<150 {
            if !child.isRunning { await waitTask.value; return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        _ = kill(child.processIdentifier, SIGKILL)
        for _ in 0..<100 {
            if !child.isRunning { await waitTask.value; return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        // Refuse another launch if the OS did not confirm termination. Keeping
        // the actual process handle prevents an unknown overlapping executor.
        process = child
    }

    private func consume(_ chunk: Chunk, generation expected: UUID) async {
        guard expected == generation else { return }
        switch chunk {
        case .ended:
            await stop(); broadcast(.init(method: "runtime/disconnected"))
        case .data(let data):
            buffer.append(data)
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                guard line.count <= maximumMessageBytes,
                      let message = try? JSONDecoder().decode(ExecutionJSON.self, from: Data(line)) else {
                    await stop(); broadcast(.init(method: "runtime/disconnected")); return
                }
                receive(message)
            }
            if buffer.count > maximumMessageBytes { await stop(); broadcast(.init(method: "runtime/disconnected")) }
        }
    }

    private func receive(_ message: ExecutionJSON) {
        if let method = message["method"].string {
            if message["id"] != .null {
                // This client does not silently approve new capabilities or interactive tools.
                // Unknown server requests terminate the turn with a visible blocker.
                try? send(.object(["id": message["id"], "error": .object([
                    "code": .number(-32601), "message": .string("This client does not support this interactive request.")])]))
                broadcast(.init(method: "runtime/requestUnsupported", params: .object([
                    "method": .string(method), "threadId": message["params"]["threadId"]])))
            } else { broadcast(.init(method: method, params: message["params"])) }
            return
        }
        guard let id = message["id"].integer else { return }
        if message["error"] != .null {
            reject(id: id, error: ExecutionError.rpcRejected(message["error"]["code"].integer ?? -1))
        } else if let value = pending.removeValue(forKey: id) {
            value.timeout.cancel(); value.continuation.resume(returning: message["result"])
        }
    }

    private func send(_ message: ExecutionJSON) throws {
        guard process?.isRunning == true, let input else { throw ExecutionError.notConnected }
        var data = try JSONEncoder().encode(message); data.append(0x0A)
        guard data.count <= maximumMessageBytes else { throw ExecutionError.malformedMessage }
        try input.write(contentsOf: data)
    }
    private func reject(id: Int, error: any Error) {
        guard let value = pending.removeValue(forKey: id) else { return }
        value.timeout.cancel(); value.continuation.resume(throwing: error)
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func broadcast(_ event: ExecutionNotification) { for observer in observers.values { observer.yield(event) } }
}
#endif

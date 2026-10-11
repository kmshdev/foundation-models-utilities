import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// File-backed output avoids pipe-buffer deadlocks and inherited-pipe EOF hangs.
/// Every command is bounded, including simulator diagnostics and cleanup.
final class NativeCommandRunner {
    let directory: URL
    private(set) var receipts: [NativeCommandReceipt] = []

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func run(_ label: String, _ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> Data {
        let prefix = String(format: "%02d", receipts.count + 1) + "-" + label
        let outputURL = directory.appendingPathComponent(prefix + ".stdout.log")
        let errorURL = directory.appendingPathComponent(prefix + ".stderr.log")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil) else {
            throw NativeCommandError.invalidOutput(label)
        }
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let started = ProcessInfo.processInfo.systemUptime
        FileHandle.standardOutput.write(Data("Running \(label) (deadline \(timeout)s): \(executable) \(arguments.joined(separator: " "))\n".utf8))
        try process.run()
        while process.isRunning && ProcessInfo.processInfo.systemUptime - started < timeout {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let terminationDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            let killDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        // Never wait for a process still running after its deadline.
        if !process.isRunning { process.waitUntilExit() }
        let receipt = NativeCommandReceipt(
            label: label, executable: executable, arguments: arguments, processID: process.processIdentifier,
            exitStatus: process.isRunning ? nil : process.terminationStatus, timedOut: timedOut,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - started,
            stdoutFile: outputURL.lastPathComponent, stderrFile: errorURL.lastPathComponent
        )
        receipts.append(receipt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: directory.appendingPathComponent("commands.json"), options: .atomic)
        try output.synchronize()
        try errors.synchronize()
        FileHandle.standardOutput.write(Data("Finished \(label): \(receipt.elapsedSeconds.formatted())s, status \(receipt.exitStatus.map(String.init) ?? "still running"), timed out \(timedOut).\n".utf8))
        if timedOut { throw NativeCommandError.timedOut(label, timeout) }
        guard process.terminationStatus == 0 else {
            throw NativeCommandError.failed(label, process.terminationStatus, try tail(errorURL))
        }
        let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16 * 1_024 * 1_024 else { throw NativeCommandError.invalidOutput(label) }
        return try Data(contentsOf: outputURL)
    }

    private func tail(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        try handle.seek(toOffset: length > 4_096 ? length - 4_096 : 0)
        return String(decoding: try handle.read(upToCount: 4_096) ?? Data(), as: UTF8.self)
    }
}

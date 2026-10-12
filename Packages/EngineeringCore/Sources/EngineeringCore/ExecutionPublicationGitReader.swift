import Foundation

public struct ExecutionPublicationGitReader: ExecutionPublicationObjectReading {
    public init() {}
    public func snapshot(for record: ExecutionRecord) async throws -> ExecutionPublicationSnapshot {
        #if os(macOS) || os(Linux)
        return try await Task { @concurrent in try read(record) }.value
        #else
        throw ExecutionError.unavailable("Publish developer commits through a connected Swift executor host.")
        #endif
    }

    #if os(macOS) || os(Linux)
    private func read(_ record: ExecutionRecord) throws -> ExecutionPublicationSnapshot {
        guard let worktree = record.worktree, let sha = record.commitSHA, validSHA(sha), validSHA(worktree.baseSHA) else {
            throw ExecutionPublicationError.invalidRecord
        }
        let directory = worktree.url
        let origin = try text(git(["remote", "get-url", "origin"], at: directory)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let origins = ["https://github.com/\(ServiceScope.repository)", "git@github.com:\(ServiceScope.repository)", "ssh://git@github.com/\(ServiceScope.repository)"]
        guard origins.contains(where: { origin == $0 || origin == $0 + ".git" }),
              try text(git(["rev-parse", "--show-object-format"], at: directory)).trimmingCharacters(in: .whitespacesAndNewlines) == "sha1" else {
            throw ExecutionPublicationError.invalidGitObject
        }
        let raw = try text(git(["cat-file", "commit", sha], at: directory))
        guard let boundary = raw.range(of: "\n\n") else { throw ExecutionPublicationError.invalidGitObject }
        let header = String(raw[..<boundary.lowerBound]), message = String(raw[boundary.upperBound...])
        let parents = header.components(separatedBy: "\n").filter { $0.hasPrefix("parent ") }.map { String($0.dropFirst(7)) }
        guard parents == [worktree.baseSHA], let treeLine = header.components(separatedBy: "\n").first(where: { $0.hasPrefix("tree ") }) else {
            throw ExecutionPublicationError.unsupportedHistory
        }
        let treeSHA = String(treeLine.dropFirst(5))
        let parentTreeSHA = try text(git(["rev-parse", "\(worktree.baseSHA)^{tree}"], at: directory)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard validSHA(treeSHA), validSHA(parentTreeSHA) else { throw ExecutionPublicationError.invalidGitObject }
        let identities = try text(git(["show", "-s", "--format=format:%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI", sha], at: directory)).components(separatedBy: "\0")
        guard identities.count == 6 else { throw ExecutionPublicationError.invalidGitObject }
        let author = ExecutionPublicationIdentity(name: identities[0], email: identities[1], date: identities[2])
        let committer = ExecutionPublicationIdentity(name: identities[3], email: identities[4], date: identities[5])
        let old = try entries(git(["ls-tree", "-r", "-z", worktree.baseSHA], at: directory))
        let new = try entries(git(["ls-tree", "-r", "-z", sha], at: directory))
        let changed = try text(git(["diff", "--no-ext-diff", "--no-renames", "--name-only", "-z", worktree.baseSHA, sha], at: directory))
            .split(separator: "\0").map(String.init).sorted()
        guard changed.count <= 100, !changed.isEmpty else { throw ExecutionPublicationError.tooLarge }
        var totalBytes = 0, changes: [ExecutionPublicationChange] = []
        for path in changed {
            _ = try PlanValidator.canonicalPath(path)
            let item = new[path] ?? old[path]
            guard let item, item.type == "blob", ["100644", "100755"].contains(item.mode) else {
                throw ExecutionPublicationError.unsupportedFileMode(item?.mode ?? "unknown")
            }
            if let current = new[path] {
                let size = try text(git(["cat-file", "-s", current.sha], at: directory)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let count = Int(size), count >= 0, count <= 4 * 1024 * 1024 else { throw ExecutionPublicationError.tooLarge }
                totalBytes += count
                guard totalBytes <= 16 * 1024 * 1024 else { throw ExecutionPublicationError.tooLarge }
                let data = try git(["cat-file", "blob", current.sha], at: directory)
                guard data.count == count else { throw ExecutionPublicationError.invalidGitObject }
                changes.append(.init(path: path, mode: current.mode, blobSHA: current.sha, content: data))
            } else { changes.append(.init(path: path, mode: item.mode, blobSHA: nil, content: nil)) }
        }
        var signature: String?
        let lines = header.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix("gpgsig ") }) {
            var value = String(lines[start].dropFirst(7))
            for line in lines.dropFirst(start + 1) {
                guard line.hasPrefix(" ") else { break }
                value += "\n" + line.dropFirst()
            }
            guard value.hasPrefix("-----BEGIN PGP SIGNATURE-----") else { throw ExecutionPublicationError.unsupportedHistory }
            signature = value
        }
        guard !lines.contains(where: { $0.hasPrefix("encoding ") || $0.hasPrefix("mergetag ") }) else {
            throw ExecutionPublicationError.unsupportedHistory
        }
        return .init(commitSHA: sha, parentSHA: worktree.baseSHA, treeSHA: treeSHA, parentTreeSHA: parentTreeSHA,
                     message: message, author: author, committer: committer, signature: signature, changes: changes)
    }

    private func entries(_ data: Data) throws -> [String: (mode: String, type: String, sha: String)] {
        var result: [String: (mode: String, type: String, sha: String)] = [:]
        for row in try text(data).split(separator: "\0") {
            guard let tab = row.firstIndex(of: "\t") else { throw ExecutionPublicationError.invalidGitObject }
            let fields = row[..<tab].split(separator: " "), path = String(row[row.index(after: tab)...])
            guard fields.count == 3, result[path] == nil, validSHA(String(fields[2])) else { throw ExecutionPublicationError.invalidGitObject }
            result[path] = (String(fields[0]), String(fields[1]), String(fields[2]))
        }
        return result
    }

    private func text(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else { throw ExecutionPublicationError.invalidGitObject }
        return value
    }
    private func validSHA(_ value: String) -> Bool { value.count == 40 && value.allSatisfy { $0.isASCII && $0.isHexDigit } }

    private func git(_ arguments: [String], at directory: URL) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = ["--no-pager"] + arguments
        process.currentDirectoryURL = directory; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment.filter { ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "USER", "LOGNAME"].contains($0.key) }
        environment["GIT_TERMINAL_PROMPT"] = "0"; environment["GIT_NO_REPLACE_OBJECTS"] = "1"
        environment["GIT_CONFIG_COUNT"] = "1"; environment["GIT_CONFIG_KEY_0"] = "core.hooksPath"; environment["GIT_CONFIG_VALUE_0"] = "/dev/null"
        process.environment = environment
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        var result = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard result.count + chunk.count <= 16 * 1024 * 1024 else { throw ExecutionPublicationError.tooLarge }
            result.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExecutionPublicationError.invalidGitObject }
        return result
    }
    #endif
}

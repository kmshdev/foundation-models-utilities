import EngineeringCore
import Foundation

#if os(macOS) || os(Linux)
/// Each task gets a new branch/worktree. Failed or cancelled work is retained;
/// the coordinator never resets, merges, pushes, or deletes a user's checkout.
public actor ExecutionGitWorktrees: ExecutionWorktreeManaging {
    private let repositoryURL: URL
    private let worktreeDirectory: URL
    private let gitURL: URL
    public init(repositoryURL: URL, worktreeDirectory: URL, gitURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.repositoryURL = repositoryURL; self.worktreeDirectory = worktreeDirectory; self.gitURL = gitURL
    }

    public func prepare(executionID: UUID, dependencyCommits: [String]) async throws -> ExecutionWorktree {
        let topLevel = try await git(["rev-parse", "--show-toplevel"], at: repositoryURL)
        guard URL(fileURLWithPath: topLevel.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path == repositoryURL.resolvingSymlinksInPath().path else {
            throw ExecutionError.invalidConfiguration("Choose the repository's root folder, not a nested source folder.")
        }
        let remote = try await git(["remote", "get-url", "origin"], at: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = ["https://github.com/\(ServiceScope.repository)", "git@github.com:\(ServiceScope.repository)",
                       "ssh://git@github.com/\(ServiceScope.repository)"]
        guard allowed.contains(where: { remote == $0 || remote == $0 + ".git" }) else {
            throw ExecutionError.invalidConfiguration("Choose a clone of \(ServiceScope.repository). This executor is scoped to that repository.")
        }
        let head = try await git(["rev-parse", "HEAD"], at: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        try validateSHA(head)
        let name = executionID.uuidString.lowercased(), branch = "engineering/\(name)"
        let url = worktreeDirectory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ExecutionError.invalidConfiguration("A worktree already exists for this execution. Its previous result has been retained; do not dispatch it twice.")
        }
        try FileManager.default.createDirectory(at: worktreeDirectory, withIntermediateDirectories: true)
        _ = try await git(["worktree", "add", "-b", branch, url.path, head], at: repositoryURL)
        var seen = Set<String>()
        for commit in dependencyCommits where seen.insert(commit).inserted {
            try validateSHA(commit)
            let ancestor = try await git(["merge-base", "HEAD", commit], at: url).trimmingCharacters(in: .whitespacesAndNewlines)
            if ancestor == commit { continue }
            _ = try await git(["cherry-pick", "--no-edit", commit], at: url)
        }
        let base = try await git(["rev-parse", "HEAD"], at: url).trimmingCharacters(in: .whitespacesAndNewlines)
        return ExecutionWorktree(url: url, branch: branch, baseSHA: base)
    }

    public func verifyAndCommit(task: WorkTask, worktree: ExecutionWorktree) async throws -> ExecutionGitReceipt {
        let branch = try await git(["symbolic-ref", "--short", "HEAD"], at: worktree.url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard branch == worktree.branch else {
            throw ExecutionError.invalidConfiguration("The developer changed its worktree branch. Its result was retained without committing or handing it off.")
        }
        // Include committed changes (if the model ignored the no-commit instruction),
        // staged/unstaged changes, untracked files, deletions and both rename paths.
        let tracked = try await git(["diff", "--no-renames", "--name-only", "-z", worktree.baseSHA], at: worktree.url)
        let untracked = try await git(["ls-files", "--others", "--exclude-standard", "-z"], at: worktree.url)
        let paths = Array(Set((tracked + untracked).split(separator: "\0").map(String.init))).sorted()
        let outside = try paths.filter { path in
            let canonical = try PlanValidator.canonicalPath(path)
            return try !task.paths.contains { owned in
                let scope = try PlanValidator.canonicalPath(owned)
                return canonical == scope || canonical.hasPrefix(scope + "/")
            }
        }
        guard outside.isEmpty else { throw ExecutionError.scopeViolation(outside) }
        for path in paths {
            let candidate = worktree.url.appendingPathComponent(path).standardizedFileURL
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(worktree.url.resolvingSymlinksInPath().path + "/") else {
                throw ExecutionError.scopeViolation([path])
            }
        }
        guard !paths.isEmpty else { return .init(changedPaths: [], commitSHA: nil) }
        // Only owned, verified paths may be staged. Literal pathspec avoids wildcard
        // interpretation even if an existing repo contains punctuation in filenames.
        _ = try await git(["--literal-pathspecs", "add", "--"] + paths, at: worktree.url)
        let staged = try await git(["diff", "--cached", "--name-only", "-z"], at: worktree.url)
        if !staged.isEmpty {
            _ = try await git(["commit", "-m", "Engineering task: \(task.title)"], at: worktree.url)
        }
        let commit = try await git(["rev-parse", "HEAD"], at: worktree.url).trimmingCharacters(in: .whitespacesAndNewlines)
        try validateSHA(commit)
        return .init(changedPaths: paths, commitSHA: commit == worktree.baseSHA ? nil : commit)
    }

    private func validateSHA(_ value: String) throws {
        guard [40, 64].contains(value.count), value.allSatisfy({ $0.isHexDigit }) else {
            throw ExecutionError.invalidConfiguration("Git returned an invalid commit identity.")
        }
    }

    private func git(_ arguments: [String], at directory: URL) async throws -> String {
        let executable = gitURL
        return try await Task { @concurrent in
            let process = Process(), output = Pipe()
            process.executableURL = executable
            // Sandboxed apps need no identity in the user's home directory.
            // These command-only settings also make commits and cherry-picks
            // noninteractive while Git retains each dependency's original author.
            process.arguments = [
                "-c", "user.name=Engineering Studio",
                "-c", "user.email=engineering-studio@localhost",
                "-c", "commit.gpgsign=false",
                "-c", "core.hooksPath=/dev/null",
                "-c", "core.fsmonitor=false"
            ] + arguments
            process.currentDirectoryURL = directory
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            // Git commands are local; discard ambient tokens and disable prompts/hooks.
            var environment = ProcessInfo.processInfo.environment.filter {
                ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "USER", "LOGNAME"].contains($0.key)
            }
            environment["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = environment
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ExecutionError.commandFailed("git \(arguments.first ?? "command")", process.terminationStatus)
            }
            guard data.count <= 8 * 1024 * 1024, let result = String(data: data, encoding: .utf8) else {
                throw ExecutionError.malformedMessage
            }
            return result
        }.value
    }
}
#endif

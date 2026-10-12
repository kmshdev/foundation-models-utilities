import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Publishes immutable, scope-verified task objects through GitHub's Git Data API.
/// No git network command, force update, merge, or ambient credential is used.
public actor ExecutionGitHubPublisher {
    private let token: String
    private let transport: any ServiceHTTPTransport
    private let objectReader: any ExecutionPublicationObjectReading
    private var publishedParents: [ExecutionPullRequestReceipt]
    private var publishing: Set<UUID> = []

    public init(token: String, transport: any ServiceHTTPTransport = URLSessionServiceTransport(),
                objectReader: any ExecutionPublicationObjectReading = ExecutionPublicationGitReader(),
                publishedParents: [ExecutionPullRequestReceipt] = []) {
        self.token = token; self.transport = transport; self.objectReader = objectReader; self.publishedParents = publishedParents
    }

    public func publish(record: ExecutionRecord) async throws -> ExecutionPullRequestReceipt {
        try validate(record)
        guard publishing.insert(record.id).inserted else { throw ExecutionPublicationError.alreadyPublishing }
        defer { publishing.remove(record.id) }
        let snapshot = try await objectReader.snapshot(for: record)
        try validate(snapshot, for: record)
        let repository = try await GitHubService(token: token, transport: transport).repository()
        try validateBranch(repository.defaultBranch)
        let base = try await resolveBase(record: record, snapshot: snapshot, defaultBranch: repository.defaultBranch)
        if snapshot.signature != nil, base.sha != snapshot.parentSHA { throw ExecutionPublicationError.unsupportedHistory }
        let branch = record.worktree!.branch
        let existingHead = try await reference(branch)
        var remoteSHA: String?
        if let existingHead, existingHead != base.sha {
            let commit = try await request("/git/commits/\(existingHead)")
            guard matches(commit, snapshot: snapshot, parentSHA: base.sha), commit["sha"].string == existingHead else {
                throw ExecutionPublicationError.branchConflict
            }
            remoteSHA = existingHead
        }
        let existingPR = try await findPullRequest(record: record, baseBranch: base.branch)
        if let existingPR {
            guard let remoteSHA else { throw ExecutionPublicationError.pullRequestConflict }
            return try await receipt(existingPR, record: record, snapshot: snapshot, remoteSHA: remoteSHA, baseBranch: base.branch)
        }
        if remoteSHA == nil {
            var entries: [ExecutionJSON] = []
            for change in snapshot.changes {
                try Task.checkCancellation()
                if let data = change.content, let sha = change.blobSHA {
                    let blob = try await request("/git/blobs", method: "POST", body: .object([
                        "content": .string(data.base64EncodedString()), "encoding": .string("base64")]))
                    guard blob["sha"].string == sha else { throw ExecutionPublicationError.invalidGitObject }
                }
                entries.append(.object(["path": .string(change.path), "mode": .string(change.mode), "type": .string("blob"),
                    "sha": change.blobSHA.map(ExecutionJSON.string) ?? .null]))
            }
            let tree = try await request("/git/trees", method: "POST", body: .object([
                "base_tree": .string(snapshot.parentTreeSHA), "tree": .array(entries)]))
            guard tree["sha"].string == snapshot.treeSHA else { throw ExecutionPublicationError.invalidGitObject }
            var payload: [String: ExecutionJSON] = ["message": .string(snapshot.message), "tree": .string(snapshot.treeSHA),
                "parents": .array([.string(base.sha)]), "author": identity(snapshot.author), "committer": identity(snapshot.committer)]
            if let signature = snapshot.signature { payload["signature"] = .string(signature) }
            let commit = try await request("/git/commits", method: "POST", body: .object(payload))
            guard let sha = commit["sha"].string, validSHA(sha), matches(commit, snapshot: snapshot, parentSHA: base.sha) else {
                throw ExecutionPublicationError.invalidGitObject
            }
            remoteSHA = sha
            try await establishReference(branch, sha: sha, previous: existingHead)
        }
        guard let remoteSHA, try await reference(branch) == remoteSHA else { throw ExecutionPublicationError.branchConflict }
        let pullRequest: ExecutionJSON
        do {
            let created = try await GitHubService(token: token, transport: transport).createDraftPullRequest(
                title: record.task.title, body: pullRequestBody(record), head: branch, base: base.branch)
            pullRequest = try await request("/pulls/\(created.number)")
        } catch {
            // A lost response may already have created the PR. Only a bounded,
            // scoped read can reconcile it; never send a second POST here.
            if let existing = try? await findPullRequest(record: record, baseBranch: base.branch) { pullRequest = existing }
            else if let definitive = definitiveFailure(error) { throw definitive }
            else { throw ExecutionPublicationError.ambiguousMutation("the draft pull request") }
        }
        return try await receipt(pullRequest, record: record, snapshot: snapshot, remoteSHA: remoteSHA, baseBranch: base.branch)
    }

    private func resolveBase(record: ExecutionRecord, snapshot: ExecutionPublicationSnapshot,
                             defaultBranch: String) async throws -> (sha: String, branch: String) {
        if let parent = try await optionalRequest("/git/commits/\(snapshot.parentSHA)") {
            guard parent["sha"].string == snapshot.parentSHA, parent["tree"]["sha"].string == snapshot.parentTreeSHA else {
                throw ExecutionPublicationError.invalidGitObject
            }
            guard let defaultHead = try await reference(defaultBranch) else { throw ExecutionPublicationError.missingParent(snapshot.parentSHA) }
            let comparison = try await request("/compare/\(snapshot.parentSHA)...\(defaultHead)")
            if ["ahead", "identical"].contains(comparison["status"].string ?? ""),
               comparison["merge_base_commit"]["sha"].string == snapshot.parentSHA {
                return (snapshot.parentSHA, defaultBranch)
            }
        }
        // A cherry-picked dependency can have a different local commit ID. Its
        // published receipt is usable only when the complete base tree matches.
        for parent in publishedParents where parent.key.outcomeID == record.key.outcomeID && record.receivedHandoffs.contains(parent.key) {
            guard validSHA(parent.remoteHeadSHA), parent.branch == "engineering/\(parent.executionID.uuidString.lowercased())" else { continue }
            let remote = try await request("/git/commits/\(parent.remoteHeadSHA)")
            guard remote["sha"].string == parent.remoteHeadSHA,
                  remote["tree"]["sha"].string == snapshot.parentTreeSHA,
                  try await reference(parent.branch) == parent.remoteHeadSHA else { continue }
            return (parent.remoteHeadSHA, parent.branch)
        }
        throw ExecutionPublicationError.missingParent(snapshot.parentSHA)
    }

    private func establishReference(_ branch: String, sha: String, previous: String?) async throws {
        do {
            let result: ExecutionJSON
            if previous != nil {
                result = try await request("/git/refs/heads/\(branch)", method: "PATCH", body: .object(["sha": .string(sha), "force": .bool(false)]))
            } else {
                result = try await request("/git/refs", method: "POST", body: .object(["ref": .string("refs/heads/\(branch)"), "sha": .string(sha)]))
            }
            guard result["ref"].string == "refs/heads/\(branch)", result["object"]["type"].string == "commit", result["object"]["sha"].string == sha else {
                throw ExecutionPublicationError.branchConflict
            }
        } catch {
            if let confirmed = try? await reference(branch), confirmed == sha { return }
            if let definitive = definitiveFailure(error) { throw definitive }
            throw ExecutionPublicationError.ambiguousMutation("the execution branch")
        }
    }

    private func reference(_ branch: String) async throws -> String? {
        try validateBranch(branch)
        guard let result = try await optionalRequest("/git/ref/heads/\(branch)") else { return nil }
        guard result["ref"].string == "refs/heads/\(branch)", result["object"]["type"].string == "commit",
              let sha = result["object"]["sha"].string, validSHA(sha) else { throw ExecutionPublicationError.branchConflict }
        return sha
    }

    private func findPullRequest(record: ExecutionRecord, baseBranch: String) async throws -> ExecutionJSON? {
        var found: ExecutionJSON?
        for page in 1...3 {
            let response = try await response("/pulls", query: [URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "head", value: "kmshdev:\(record.worktree!.branch)"),
                URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))])
            let data = try decode(response.data)
            guard case .array(let pulls) = data else { throw ServiceClientError.invalidResponse }
            for pull in pulls {
                guard pull["head"]["ref"].string == record.worktree!.branch,
                      pull["head"]["repo"]["full_name"].string?.lowercased() == ServiceScope.repository else { throw ExecutionPublicationError.pullRequestConflict }
                guard found == nil else { throw ExecutionPublicationError.pullRequestConflict }
                guard pull["state"].string == "open" else { throw ExecutionPublicationError.closedPullRequest }
                guard pull["draft"] == .bool(true), pull["base"]["ref"].string == baseBranch,
                      pull["base"]["repo"]["full_name"].string?.lowercased() == ServiceScope.repository,
                      pull["body"].string?.contains(marker(record)) == true else { throw ExecutionPublicationError.pullRequestConflict }
                found = pull
            }
            let more = response.headers["link"]?.contains("rel=\"next\"") == true
            if !more { return found }
        }
        throw ExecutionPublicationError.pullRequestConflict
    }

    private func receipt(_ pull: ExecutionJSON, record: ExecutionRecord, snapshot: ExecutionPublicationSnapshot,
                         remoteSHA: String, baseBranch: String) async throws -> ExecutionPullRequestReceipt {
        guard let number = pull["number"].integer, number > 0,
              let urlText = pull["html_url"].string, let url = URL(string: urlText),
              url.scheme == "https", url.host == "github.com", url.query == nil, url.fragment == nil,
              url.path == "/\(ServiceScope.repository)/pull/\(number)",
              pull["state"].string == "open", pull["draft"] == .bool(true),
              pull["head"]["ref"].string == record.worktree?.branch, pull["head"]["sha"].string == remoteSHA,
              pull["head"]["repo"]["full_name"].string?.lowercased() == ServiceScope.repository,
              pull["base"]["ref"].string == baseBranch,
              pull["base"]["repo"]["full_name"].string?.lowercased() == ServiceScope.repository,
              pull["body"].string?.contains(marker(record)) == true,
              try await reference(record.worktree!.branch) == remoteSHA else { throw ExecutionPublicationError.pullRequestConflict }
        let receipt = ExecutionPullRequestReceipt(executionID: record.id, key: record.key, pullRequestNumber: number, url: url,
            branch: record.worktree!.branch, baseBranch: baseBranch, remoteHeadSHA: remoteSHA,
            localCommitSHA: snapshot.commitSHA, remoteTreeSHA: snapshot.treeSHA)
        publishedParents.removeAll { $0.key == receipt.key }; publishedParents.append(receipt)
        return receipt
    }

    private func validate(_ record: ExecutionRecord) throws {
        guard !token.isEmpty, !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ServiceClientError.missingCredential }
        guard record.status == .completed, let sha = record.commitSHA, validSHA(sha),
              let worktree = record.worktree, validSHA(worktree.baseSHA), sha != worktree.baseSHA,
              worktree.branch == "engineering/\(record.id.uuidString.lowercased())", !record.changedPaths.isEmpty,
              let result = record.result, result.disposition == .completed, result.blocker.isEmpty,
              Set(result.acceptedCriteria) == Set(record.task.acceptance), !record.task.acceptance.isEmpty,
              result.acceptedCriteria.count == Set(result.acceptedCriteria).count else { throw ExecutionPublicationError.invalidRecord }
        for path in record.changedPaths { try validateScope(path, task: record.task) }
    }

    private func validate(_ snapshot: ExecutionPublicationSnapshot, for record: ExecutionRecord) throws {
        guard snapshot.commitSHA == record.commitSHA, snapshot.parentSHA == record.worktree?.baseSHA,
              validSHA(snapshot.treeSHA), validSHA(snapshot.parentTreeSHA), snapshot.treeSHA != snapshot.parentTreeSHA,
              !snapshot.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.changes.count <= 100, !snapshot.changes.isEmpty,
              Set(snapshot.changes.map(\.path)) == Set(record.changedPaths),
              Set(snapshot.changes.map(\.path)).count == snapshot.changes.count else { throw ExecutionPublicationError.invalidGitObject }
        for person in [snapshot.author, snapshot.committer] {
            guard !person.name.isEmpty, !person.email.isEmpty, date(person.date) != nil,
                  !person.name.contains("\n"), !person.email.contains("\n") else { throw ExecutionPublicationError.invalidGitObject }
        }
        var size = 0
        for change in snapshot.changes {
            try validateScope(change.path, task: record.task)
            guard ["100644", "100755"].contains(change.mode),
                  (change.blobSHA == nil) == (change.content == nil) else { throw ExecutionPublicationError.invalidGitObject }
            if let sha = change.blobSHA, let data = change.content {
                guard validSHA(sha), data.count <= 4 * 1024 * 1024 else { throw ExecutionPublicationError.tooLarge }
                size += data.count
            }
        }
        guard size <= 16 * 1024 * 1024 else { throw ExecutionPublicationError.tooLarge }
    }

    private func validateScope(_ path: String, task: WorkTask) throws {
        let value = try PlanValidator.canonicalPath(path)
        guard !value.split(separator: "/").contains(".git"), try task.paths.contains(where: { scope in
            let allowed = try PlanValidator.canonicalPath(scope); return value == allowed || value.hasPrefix(allowed + "/")
        }) else { throw ExecutionError.scopeViolation([path]) }
    }
    private func matches(_ commit: ExecutionJSON, snapshot: ExecutionPublicationSnapshot, parentSHA: String) -> Bool {
        commit["tree"]["sha"].string == snapshot.treeSHA && commit["parents"].array.map { $0["sha"].string ?? "" } == [parentSHA] &&
        commit["message"].string?.trimmingCharacters(in: .newlines) == snapshot.message.trimmingCharacters(in: .newlines) &&
        matchesIdentity(commit["author"], snapshot.author) && matchesIdentity(commit["committer"], snapshot.committer) &&
        (snapshot.signature == nil || commit["verification"]["signature"].string == snapshot.signature)
    }
    private func matchesIdentity(_ value: ExecutionJSON, _ expected: ExecutionPublicationIdentity) -> Bool {
        value["name"].string == expected.name && value["email"].string == expected.email &&
        value["date"].string.flatMap(date) == date(expected.date)
    }
    private func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }
    private func identity(_ value: ExecutionPublicationIdentity) -> ExecutionJSON {
        .object(["name": .string(value.name), "email": .string(value.email), "date": .string(value.date)])
    }
    private func validSHA(_ value: String) -> Bool { value.count == 40 && value.allSatisfy { $0.isASCII && $0.isHexDigit } }
    private func definitiveFailure(_ error: any Error) -> (any Error)? {
        if let error = error as? ServiceClientError, case .http(let status, _) = error {
            if [401, 403].contains(status) { return ExecutionPublicationError.githubWriteDenied(status) }
            if (400..<500).contains(status), status != 408, status != 429 { return error }
        }
        if let error = error as? ExecutionPublicationError { return error }
        return nil
    }
    private func validateBranch(_ value: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains(".."), !value.contains("//"),
              !value.hasSuffix(".lock"), value.unicodeScalars.allSatisfy(allowed.contains) else { throw ServiceClientError.invalidInput("branch") }
    }
    private func marker(_ record: ExecutionRecord) -> String { "<!-- engineering-studio-execution:\(record.id.uuidString.lowercased()):\(record.commitSHA!) -->" }
    private func pullRequestBody(_ record: ExecutionRecord) -> String {
        """
        \(record.summary)

        Outcome/task: \(record.key.id)
        Owner: \(record.task.owner.title)
        Local source commit: \(record.commitSHA!)
        Scoped files: \(record.changedPaths.joined(separator: ", "))

        Acceptance attested by the developer:
        \(record.task.acceptance.map { "- \($0)" }.joined(separator: "\n"))

        Observed command receipts:
        \(record.commands.map { "- `\($0.command)` — exit \($0.exitCode.map(String.init) ?? "unknown"), \($0.status)" }.joined(separator: "\n"))

        The remote commit ID is verified separately. Command receipts describe observed commands; they do not imply a total count of passed tests. This pull request remains a draft.

        \(marker(record))
        """
    }

    private func optionalRequest(_ path: String) async throws -> ExecutionJSON? {
        let response = try await response(path, allowNotFound: true)
        return response.statusCode == 404 ? nil : try decode(response.data)
    }
    private func request(_ path: String, method: String = "GET", body: ExecutionJSON? = nil) async throws -> ExecutionJSON {
        try decode(await response(path, method: method, body: body).data)
    }
    private func decode(_ data: Data) throws -> ExecutionJSON {
        guard data.count <= 32 * 1024 * 1024, let value = try? JSONDecoder().decode(ExecutionJSON.self, from: data) else { throw ServiceClientError.invalidResponse }
        return value
    }
    private func response(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: ExecutionJSON? = nil,
                          allowNotFound: Bool = false) async throws -> ServiceHTTPResponse {
        try Task.checkCancellation()
        var components = URLComponents(string: "https://api.github.com/repos/\(ServiceScope.repository)\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("EngineeringStudio", forHTTPHeaderField: "User-Agent")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result = try await transport.send(request)
        if method != "GET", [401, 403].contains(result.statusCode), result.headers["x-ratelimit-remaining"] != "0", result.headers["retry-after"] == nil {
            throw ExecutionPublicationError.githubWriteDenied(result.statusCode)
        }
        guard (200..<300).contains(result.statusCode) || (allowNotFound && result.statusCode == 404) else {
            throw ServiceClientError.http(status: result.statusCode, retryAfter: result.headers["retry-after"])
        }
        return result
    }
}

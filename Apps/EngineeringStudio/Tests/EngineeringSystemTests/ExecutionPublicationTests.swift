import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import EngineeringCore
@testable import EngineeringServices

private struct PublicationReader: ExecutionPublicationObjectReading {
    let value: ExecutionPublicationSnapshot
    func snapshot(for record: ExecutionRecord) -> ExecutionPublicationSnapshot { value }
}

private struct PublicationFixture: Sendable {
    let record: ExecutionRecord
    let snapshot: ExecutionPublicationSnapshot
    static func make() -> PublicationFixture {
        let sha = String(repeating: "a", count: 40), parent = String(repeating: "b", count: 40)
        let task = WorkTask(id: "scoped-task", title: "Build scoped Swift behavior", owner: .architecture,
            paths: ["Owned.swift"], acceptance: ["Implement the behavior"], dependencies: [], handoff: "Share the verified result")
        var record = ExecutionRecord(key: .init(outcomeID: UUID(), taskID: task.id), outcome: "Build", task: task)
        record.status = .completed; record.changedPaths = ["Owned.swift"]; record.commitSHA = sha
        record.worktree = .init(url: URL(fileURLWithPath: "/tmp/fixture"), branch: "engineering/\(record.id.uuidString.lowercased())", baseSHA: parent)
        record.result = .init(disposition: .completed, summary: "Implemented", acceptedCriteria: task.acceptance, blocker: "")
        record.summary = "Implemented"
        let identity = ExecutionPublicationIdentity(name: "Swift Developer", email: "developer@example.invalid", date: "2026-10-12T00:00:00Z")
        let snapshot = ExecutionPublicationSnapshot(commitSHA: sha, parentSHA: parent, treeSHA: String(repeating: "c", count: 40),
            parentTreeSHA: String(repeating: "d", count: 40), message: "Scoped commit\n", author: identity, committer: identity,
            changes: [.init(path: "Owned.swift", mode: "100644", blobSHA: String(repeating: "e", count: 40), content: Data([0, 1, 2, 255]))])
        return .init(record: record, snapshot: snapshot)
    }
}

private actor PublicationTransport: ServiceHTTPTransport {
    let fixture: PublicationFixture
    var requests: [URLRequest] = []
    var head: String?
    var parentMissing = false
    var losePR = false
    var loseRef = false
    var closed = false
    var pull: ExecutionJSON?
    var stackedParent: ExecutionPullRequestReceipt?
    let remoteSHA = String(repeating: "f", count: 40)
    init(_ fixture: PublicationFixture) { self.fixture = fixture }
    func configure(head: String? = nil, parentMissing: Bool = false, losePR: Bool = false, loseRef: Bool = false,
                   closed: Bool = false, stackedParent: ExecutionPullRequestReceipt? = nil) {
        self.head = head; self.parentMissing = parentMissing; self.losePR = losePR; self.loseRef = loseRef
        self.closed = closed; self.stackedParent = stackedParent
    }
    func send(_ request: URLRequest) throws -> ServiceHTTPResponse {
        requests.append(request)
        let prefix = "/repos/\(ServiceScope.repository)"
        let path = String(request.url!.path.dropFirst(prefix.count)), method = request.httpMethod ?? "GET"
        let body = request.httpBody.flatMap { try? JSONDecoder().decode(ExecutionJSON.self, from: $0) } ?? .null
        let branch = fixture.record.worktree!.branch, snapshot = fixture.snapshot
        if path == "", method == "GET" {
            return response(.object(["id": .number(1), "full_name": .string(ServiceScope.repository), "default_branch": .string("main"),
                "html_url": .string("https://github.com/\(ServiceScope.repository)")]))
        }
        if path == "/git/commits/\(snapshot.parentSHA)", method == "GET" {
            return parentMissing ? response(.object([:]), status: 404) : response(.object([
                "sha": .string(snapshot.parentSHA), "tree": .object(["sha": .string(snapshot.parentTreeSHA)])]))
        }
        if path == "/git/ref/heads/main", method == "GET" { return response(reference("main", snapshot.parentSHA)) }
        if path.hasPrefix("/compare/"), method == "GET" {
            return response(.object(["status": .string("identical"), "merge_base_commit": .object(["sha": .string(snapshot.parentSHA)])]))
        }
        if let parent = stackedParent {
            if path == "/git/commits/\(parent.remoteHeadSHA)", method == "GET" {
                return response(.object(["sha": .string(parent.remoteHeadSHA), "tree": .object(["sha": .string(snapshot.parentTreeSHA)])]))
            }
            if path == "/git/ref/heads/\(parent.branch)", method == "GET" { return response(reference(parent.branch, parent.remoteHeadSHA)) }
        }
        if path == "/git/ref/heads/\(branch)", method == "GET" {
            return head.map { response(reference(branch, $0)) } ?? response(.object([:]), status: 404)
        }
        if path.hasPrefix("/git/commits/"), method == "GET" {
            let sha = String(path.split(separator: "/").last!)
            return response(commit(sha, tree: sha == remoteSHA ? snapshot.treeSHA : String(repeating: "0", count: 40)))
        }
        if path == "/pulls", method == "GET" { return response(.array(pull.map { [$0] } ?? [])) }
        if path == "/git/blobs", method == "POST" { return response(.object(["sha": .string(snapshot.changes.first!.blobSHA!)]), status: 201) }
        if path == "/git/trees", method == "POST" { return response(.object(["sha": .string(snapshot.treeSHA)]), status: 201) }
        if path == "/git/commits", method == "POST" { return response(commit(remoteSHA, tree: snapshot.treeSHA), status: 201) }
        if path == "/git/refs" && method == "POST" || path == "/git/refs/heads/\(branch)" && method == "PATCH" {
            head = body["sha"].string
            if loseRef { loseRef = false; throw URLError(.networkConnectionLost) }
            return response(reference(branch, head!), status: method == "POST" ? 201 : 200)
        }
        if path == "/pulls", method == "POST" {
            pull = .object(["id": .number(99), "number": .number(7), "title": .string(fixture.record.task.title),
                "state": .string(closed ? "closed" : "open"), "draft": .bool(true), "body": body["body"],
                "html_url": .string("https://github.com/\(ServiceScope.repository)/pull/7"),
                "head": .object(["ref": .string(branch), "sha": .string(head!), "repo": .object(["full_name": .string(ServiceScope.repository)])]),
                "base": .object(["ref": body["base"], "sha": .string(snapshot.parentSHA), "repo": .object(["full_name": .string(ServiceScope.repository)])])])
            if losePR { losePR = false; throw URLError(.networkConnectionLost) }
            return response(pull!, status: 201)
        }
        if path == "/pulls/7", method == "GET", let pull { return response(pull) }
        throw ServiceClientError.invalidInput("unexpected test request")
    }
    func count(method: String, path: String) -> Int { requests.filter { $0.httpMethod == method && $0.url?.path.hasSuffix(path) == true }.count }
    func all() -> [URLRequest] { requests }
    private func reference(_ branch: String, _ sha: String) -> ExecutionJSON {
        .object(["ref": .string("refs/heads/\(branch)"), "object": .object(["type": .string("commit"), "sha": .string(sha)])])
    }
    private func commit(_ sha: String, tree: String) -> ExecutionJSON {
        let person: ExecutionJSON = .object(["name": .string(fixture.snapshot.author.name), "email": .string(fixture.snapshot.author.email), "date": .string(fixture.snapshot.author.date)])
        return .object(["sha": .string(sha), "tree": .object(["sha": .string(tree)]),
            "parents": .array([.object(["sha": .string(stackedParent?.remoteHeadSHA ?? fixture.snapshot.parentSHA)])]),
            "message": .string(fixture.snapshot.message), "author": person, "committer": person])
    }
    private func response(_ value: ExecutionJSON, status: Int = 200) -> ServiceHTTPResponse {
        .init(data: try! JSONEncoder().encode(value), statusCode: status)
    }
}

@Suite struct ExecutionPublicationTests {
    @Test func createsExactImmutableObjectsAndReturnsSeparateRemoteReceipt() async throws {
        let fixture = PublicationFixture.make(), transport = PublicationTransport(fixture)
        let publisher = ExecutionGitHubPublisher(token: "fixture-token", transport: transport, objectReader: PublicationReader(value: fixture.snapshot))
        let receipt = try await publisher.publish(record: fixture.record)
        #expect(receipt.pullRequestNumber == 7)
        #expect(receipt.localCommitSHA == fixture.snapshot.commitSHA)
        #expect(receipt.remoteHeadSHA == String(repeating: "f", count: 40))
        #expect(receipt.localCommitSHA != receipt.remoteHeadSHA)
        #expect(receipt.baseBranch == "main")
        let requests = await transport.all()
        #expect(requests.allSatisfy { $0.url?.host == "api.github.com" && $0.url?.path.hasPrefix("/repos/\(ServiceScope.repository)") == true })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        let blobRequest = try #require(requests.first { $0.httpMethod == "POST" && $0.url!.path.hasSuffix("/git/blobs") })
        let blobBody = try JSONDecoder().decode(ExecutionJSON.self, from: #require(blobRequest.httpBody))
        #expect(blobBody["encoding"].string == "base64")
        #expect(Data(base64Encoded: try #require(blobBody["content"].string)) == fixture.snapshot.changes[0].content)
        let commitRequest = try #require(requests.first { $0.httpMethod == "POST" && $0.url!.path.hasSuffix("/git/commits") })
        let commitBody = try JSONDecoder().decode(ExecutionJSON.self, from: #require(commitRequest.httpBody))
        #expect(commitBody["parents"].array == [.string(fixture.snapshot.parentSHA)])
        #expect(commitBody["author"]["date"].string == fixture.snapshot.author.date)
        #expect(commitBody["message"].string == fixture.snapshot.message)
        _ = try await publisher.publish(record: fixture.record)
        #expect(await transport.count(method: "POST", path: "/pulls") == 1)
        #expect(await transport.count(method: "POST", path: "/git/commits") == 1)
    }

    @Test func refusalBeforeMutationForMissingParentAndUnrelatedBranch() async throws {
        let fixture = PublicationFixture.make(), missing = PublicationTransport(fixture)
        await missing.configure(parentMissing: true)
        let missingPublisher = ExecutionGitHubPublisher(token: "fixture-token", transport: missing, objectReader: PublicationReader(value: fixture.snapshot))
        await #expect(throws: ExecutionPublicationError.missingParent(fixture.snapshot.parentSHA)) { try await missingPublisher.publish(record: fixture.record) }
        #expect(await missing.all().allSatisfy { $0.httpMethod == "GET" })
        let conflict = PublicationTransport(fixture); await conflict.configure(head: String(repeating: "9", count: 40))
        let conflictPublisher = ExecutionGitHubPublisher(token: "fixture-token", transport: conflict, objectReader: PublicationReader(value: fixture.snapshot))
        await #expect(throws: ExecutionPublicationError.branchConflict) { try await conflictPublisher.publish(record: fixture.record) }
        #expect(await conflict.all().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func outOfScopeAndUncompletedRecordsNeverSendCredential() async throws {
        let fixture = PublicationFixture.make(), transport = PublicationTransport(fixture)
        let publisher = ExecutionGitHubPublisher(token: "fixture-token", transport: transport, objectReader: PublicationReader(value: fixture.snapshot))
        var record = fixture.record; record.status = .running
        await #expect(throws: ExecutionPublicationError.invalidRecord) { try await publisher.publish(record: record) }
        record = fixture.record; record.changedPaths = ["Outside.swift"]
        await #expect(throws: ExecutionError.scopeViolation(["Outside.swift"])) { try await publisher.publish(record: record) }
        #expect(await transport.all().isEmpty)
    }

    @Test func lostReferenceAndPullRequestResponsesRecoverWithoutDuplicateWrites() async throws {
        let fixture = PublicationFixture.make(), transport = PublicationTransport(fixture)
        await transport.configure(losePR: true, loseRef: true)
        let publisher = ExecutionGitHubPublisher(token: "fixture-token", transport: transport, objectReader: PublicationReader(value: fixture.snapshot))
        let receipt = try await publisher.publish(record: fixture.record)
        #expect(receipt.pullRequestNumber == 7)
        _ = try await publisher.publish(record: fixture.record)
        #expect(await transport.count(method: "POST", path: "/pulls") == 1)
        #expect(await transport.count(method: "POST", path: "/git/refs") == 1)
    }

    @Test func knownParentReferenceUsesOnlyFastForwardUpdate() async throws {
        let fixture = PublicationFixture.make(), transport = PublicationTransport(fixture)
        await transport.configure(head: fixture.snapshot.parentSHA)
        let publisher = ExecutionGitHubPublisher(token: "fixture-token", transport: transport, objectReader: PublicationReader(value: fixture.snapshot))
        _ = try await publisher.publish(record: fixture.record)
        let request = try #require(await transport.all().first { $0.httpMethod == "PATCH" })
        let body = try JSONDecoder().decode(ExecutionJSON.self, from: #require(request.httpBody))
        #expect(body["force"] == .bool(false))
        #expect(await transport.count(method: "POST", path: "/git/refs") == 0)
    }

    @Test func cherryPickedParentUsesVerifiedEquivalentTreeAndStackedPRBase() async throws {
        let fixture = PublicationFixture.make(), transport = PublicationTransport(fixture), parentID = UUID()
        let key = ExecutionTaskKey(outcomeID: fixture.record.key.outcomeID, taskID: "dependency")
        let parent = ExecutionPullRequestReceipt(executionID: parentID, key: key, pullRequestNumber: 6,
            url: URL(string: "https://github.com/\(ServiceScope.repository)/pull/6")!, branch: "engineering/\(parentID.uuidString.lowercased())",
            baseBranch: "main", remoteHeadSHA: String(repeating: "1", count: 40), localCommitSHA: String(repeating: "2", count: 40), remoteTreeSHA: fixture.snapshot.parentTreeSHA)
        var record = fixture.record; record.receivedHandoffs = [key]
        await transport.configure(parentMissing: true, stackedParent: parent)
        let publisher = ExecutionGitHubPublisher(token: "fixture-token", transport: transport,
            objectReader: PublicationReader(value: fixture.snapshot), publishedParents: [parent])
        let receipt = try await publisher.publish(record: record)
        #expect(receipt.baseBranch == parent.branch)
        let commit = try #require(await transport.all().first { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/git/commits") == true })
        let body = try JSONDecoder().decode(ExecutionJSON.self, from: #require(commit.httpBody))
        #expect(body["parents"].array == [.string(parent.remoteHeadSHA)])
    }

    #if os(macOS) || os(Linux)
    @Test func realGitReaderUsesCommittedBytesAndModeDespiteDirtyCheckout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Owned.swift")
        try "base\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try git(["init"], at: directory)
        _ = try git(["config", "user.name", "Swift Developer"], at: directory)
        _ = try git(["config", "user.email", "developer@example.invalid"], at: directory)
        _ = try git(["remote", "add", "origin", "https://github.com/\(ServiceScope.repository).git"], at: directory)
        _ = try git(["add", "Owned.swift"], at: directory)
        _ = try git(["commit", "-m", "Base"], at: directory)
        let parent = try git(["rev-parse", "HEAD"], at: directory).trimmingCharacters(in: .whitespacesAndNewlines)
        try "committed Swift bytes\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        _ = try git(["add", "Owned.swift"], at: directory)
        _ = try git(["commit", "-m", "Scoped commit"], at: directory)
        let commit = try git(["rev-parse", "HEAD"], at: directory).trimmingCharacters(in: .whitespacesAndNewlines)
        var record = PublicationFixture.make().record
        record.commitSHA = commit
        record.worktree = .init(url: directory, branch: "engineering/\(record.id.uuidString.lowercased())", baseSHA: parent)
        try "UNCOMMITTED CONTENT MUST NOT BE UPLOADED\n".write(to: file, atomically: true, encoding: .utf8)
        let snapshot = try await ExecutionPublicationGitReader().snapshot(for: record)
        #expect(snapshot.commitSHA == commit)
        #expect(snapshot.parentSHA == parent)
        #expect(snapshot.changes.count == 1)
        #expect(snapshot.changes[0].mode == "100755")
        #expect(snapshot.changes[0].content == Data("committed Swift bytes\n".utf8))
        #expect(snapshot.message == "Scoped commit\n")
        #expect(snapshot.author.name == "Swift Developer")
    }

    private func git(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments
        process.currentDirectoryURL = directory; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let value = String(data: data, encoding: .utf8) else { throw ExecutionPublicationError.invalidGitObject }
        return value
    }
    #endif
}

@testable import WorkspaceFeature
@testable import StudioWorkflows
@testable import StudioServices
import StudioUI
import EngineeringWorkflows
import EngineeringServices
import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the real connection model and StudioStore with deterministic service receipts.
/// No credentials, network requests, or Keychain writes reach an external service.
@MainActor
func checkServiceConnections() async throws {
    let journal = ServiceCheckJournal()
    let vault = MemoryConnectionCredentials(journal: journal)
    let transport = ServiceCheckTransport(journal: journal)
    let connections = ServiceConnections(credentialStore: vault, transport: transport)
    try serviceRequire(journal.events.isEmpty, "Model initialization performs no I/O")

    transport.rejectProject = true
    try serviceRequire(!(await connections.connectLinear(token: "fixture-linear")), "Invalid project access rejects connection")
    try serviceRequire(vault.values.isEmpty && !connections.hasLinearCredential, "Rejected verification never saves a credential")
    transport.rejectProject = false
    journal.events = []
    try serviceRequire(await connections.connectLinear(token: "fixture-linear"), "Verified Linear connection succeeds")
    let verifiedIndex = journal.events.firstIndex(of: "verified-project")
    let savedIndex = journal.events.firstIndex(of: "save-linear")
    try serviceRequire(verifiedIndex != nil && savedIndex != nil && verifiedIndex! < savedIndex!,
                       "Project verification precedes credential persistence")
    try serviceRequire(connections.project?.id == ServiceScope.linearProjectID && connections.hasLinearCredential,
                       "Successful verification and persistence expose the connection")
    let previousProject = connections.project?.id
    let previousUpdate = connections.linearUpdatedAt
    transport.failReads = true
    await connections.refreshLinear()
    try serviceRequire(connections.project?.id == previousProject && connections.linearUpdatedAt == previousUpdate &&
                       connections.linearStatus.contains("Showing previous results") && connections.linearError != nil,
                       "Failed refresh retains last good data with a visible stale state")
    transport.failReads = false

    let failingVault = MemoryConnectionCredentials(journal: ServiceCheckJournal())
    failingVault.failWrites = true
    let failingConnection = ServiceConnections(credentialStore: failingVault,
                                               transport: ServiceCheckTransport(journal: ServiceCheckJournal()))
    try serviceRequire(!(await failingConnection.connectLinear(token: "fixture-linear")) &&
                       !failingConnection.hasLinearCredential && failingVault.values.isEmpty,
                       "Keychain write failure does not claim a connected credential")

    let unreadableVault = MemoryConnectionCredentials(journal: ServiceCheckJournal())
    unreadableVault.failReads = true
    let unreadableConnection = ServiceConnections(credentialStore: unreadableVault,
                                                  transport: ServiceCheckTransport(journal: ServiceCheckJournal()))
    await unreadableConnection.load()
    try serviceRequire(unreadableConnection.repository != nil && unreadableConnection.githubError != nil &&
                       unreadableConnection.githubStatus.contains("Credential unavailable") &&
                       !unreadableConnection.hasGitHubCredential,
                       "Successful public refresh preserves the failed Keychain read warning")

    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("workspace.json")
    let repository = WorkspaceRepository(url: url)
    var workspace = Workspace()
    let outcomeID = try workspace.recordOutcome("Build native engineering room")
    let task = WorkTask(id: "native-navigation", title: "Build native navigation", owner: .interface,
                        paths: ["Apps/Navigation.swift"], acceptance: ["Keyboard navigation works"],
                        dependencies: [], handoff: "Pass changed files and verification evidence to testing")
    try workspace.attach(WorkPlan(summary: "Native navigation", tasks: [task]), to: outcomeID)
    try await repository.save(workspace)
    let store = StudioStore(repository: repository)
    await store.load()
    let outcome = store.workspace.outcomes[0]
    transport.loseNextCreateResponse = true
    await connections.publishPlan(for: outcome, store: store)
    try serviceRequire(connections.publicationError == nil && transport.created.count == 1,
                       "A lost create response recovers the existing issue")
    guard let binding = store.issueBinding(outcomeID: outcomeID, taskID: task.id) else {
        throw serviceFailure("Publication has no durable binding")
    }
    try serviceRequire(binding.identifier == "EWA-1" && transport.created[binding.issueID.uuidString.lowercased()] != nil,
                       "Recovered receipt matches the UUID reserved before creation")
    let diskBinding = try await repository.load().issueBinding(outcomeID: outcomeID, taskID: task.id)
    try serviceRequire(diskBinding?.issueID == binding.issueID && diskBinding?.identifier == binding.identifier,
                       "Recovered receipt is durable")
    let initialCreates = transport.createAttempts
    let initialUpdates = transport.updateAttempts
    await connections.publishPlan(for: outcome, store: store)
    try serviceRequire(connections.publicationError == nil && transport.created.count == 1 &&
                       transport.createAttempts == initialCreates && transport.updateAttempts == initialUpdates + 1,
                       "Repeat publication updates the existing issue without creating a duplicate")

    // Persisting a reservation must succeed before any mutation is sent.
    let savedData = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let writeCount = transport.createAttempts + transport.updateAttempts
    await connections.publishPlan(for: outcome, store: store)
    try serviceRequire(connections.publicationError != nil &&
                       transport.createAttempts + transport.updateAttempts == writeCount,
                       "Persistence failure blocks HTTP mutations")
    try FileManager.default.removeItem(at: url)
    try savedData.write(to: url, options: .atomic)
    try serviceRequire(await store.flushPendingChanges(), "Test store flush completes after disk recovery")

    try await checkPublicationStopsOnPlanChange(in: directory)

    connections.disconnectLinear()
    try serviceRequire(vault.values["linear"] == nil && !connections.hasLinearCredential &&
                       connections.project == nil && connections.issues.isEmpty && connections.linearUpdatedAt == nil &&
                       connections.publicationStatus == nil && connections.publicationError == nil,
                       "Disconnect clears Linear credentials, data and publication feedback")
    try serviceRequire(await connections.connectGitHub(token: "fixture-github"), "GitHub credential connects after repository verification")
    transport.failReads = true
    await connections.disconnectGitHub()
    try serviceRequire(vault.values["github"] == nil && !connections.hasGitHubCredential &&
                       connections.repository == nil && connections.pullRequests.isEmpty && connections.workflowRuns.isEmpty,
                       "GitHub disconnect cannot retain credential-backed data after a public refresh failure")
    print("Service connection checks passed: verified credential storage, stale refresh state, Keychain failure, durable publication, lost-response recovery, duplicate prevention and disconnect.")
}

@MainActor private final class ServiceCheckJournal { var events: [String] = [] }

@MainActor private final class MemoryConnectionCredentials: ConnectionCredentialStore {
    var values: [String: String] = [:]
    var failWrites = false
    var failReads = false
    let journal: ServiceCheckJournal
    init(journal: ServiceCheckJournal) { self.journal = journal }
    func read(_ account: String) throws -> String? {
        journal.events.append("read-\(account)")
        if failReads { throw serviceFailure("Controlled credential read failure") }
        return values[account]
    }
    func write(_ value: String?, account: String) throws {
        if failWrites { throw serviceFailure("Controlled credential write failure") }
        journal.events.append("save-\(account)")
        values[account] = value
    }
}

@MainActor private final class ServiceCheckTransport: ServiceHTTPTransport {
    var rejectProject = false
    var failReads = false
    var loseNextCreateResponse = false
    var pauseNextCreateResponse = false
    private var pausedCreateResponse: CheckedContinuation<Void, Never>?
    var createResponseIsPaused: Bool { pausedCreateResponse != nil }
    func resumeCreateResponse() {
        let continuation = pausedCreateResponse
        pausedCreateResponse = nil
        continuation?.resume()
    }
    var created: [String: [String: Any]] = [:]
    var createAttempts = 0
    var updateAttempts = 0
    let journal: ServiceCheckJournal
    init(journal: ServiceCheckJournal) { self.journal = journal }

    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        guard let url = request.url else { throw serviceFailure("Missing request URL") }
        if url.host == "api.github.com" {
            if failReads { throw URLError(.notConnectedToInternet) }
            if url.path.hasSuffix("/pulls") { return try result([]) }
            if url.path.hasSuffix("/actions/runs") { return try result(["workflow_runs": []]) }
            journal.events.append("verified-repository")
            return try result(["id": 1, "full_name": ServiceScope.repository, "default_branch": "swift-app",
                               "html_url": "https://github.com/\(ServiceScope.repository)"])
        }
        guard url.absoluteString == "https://api.linear.app/graphql", let data = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = body["query"] as? String,
              let variables = body["variables"] as? [String: Any] else { throw serviceFailure("Unexpected fixture request") }
        if query.contains("mutation StudioCreateIssue") {
            createAttempts += 1
            guard let input = variables["input"] as? [String: Any], let id = input["id"] as? String else {
                throw serviceFailure("Creation requires the durable reserved UUID")
            }
            let existed = created[id] != nil
            if !existed {
                created[id] = issue(id: id, title: input["title"] as? String ?? "Untitled")
                created[id]?["description"] = input["description"]
            }
            if pauseNextCreateResponse {
                pauseNextCreateResponse = false
                await withCheckedContinuation { pausedCreateResponse = $0 }
            }
            if existed { throw ServiceClientError.graphQL }
            if loseNextCreateResponse {
                loseNextCreateResponse = false
                throw URLError(.networkConnectionLost)
            }
            return try result(["data": ["issueCreate": ["success": true, "issue": created[id]!]]])
        }
        if query.contains("mutation StudioUpdateIssue") {
            updateAttempts += 1
            guard let id = variables["id"] as? String, var existing = created[id],
                  let input = variables["input"] as? [String: Any] else { throw serviceFailure("Update requires an existing issue") }
            existing["title"] = input["title"]
            existing["description"] = input["description"]
            created[id] = existing
            return try result(["data": ["issueUpdate": ["success": true, "issue": existing]]])
        }
        if failReads { throw URLError(.notConnectedToInternet) }
        if query.contains("query StudioIssue(") {
            let id = (variables["id"] as? String ?? "").lowercased()
            return try result(["data": ["issue": created[id] as Any? ?? NSNull()]])
        }
        if query.contains("query StudioIssues(") {
            return try result(["data": ["project": ["id": ServiceScope.linearProjectID,
                "issues": ["nodes": Array(created.values), "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]]])
        }
        if query.contains("query StudioProject(") {
            if rejectProject { throw ServiceClientError.scopeMismatch }
            journal.events.append("verified-project")
            return try result(["data": ["project": ["id": ServiceScope.linearProjectID,
                "name": "Engineering Workflow Automation", "url": "https://linear.app/kmsh-dev/project/engineering-workflow-automation-93f936d49f78"]]])
        }
        throw serviceFailure("Unexpected GraphQL operation")
    }

    func seedIssue(id: String, title: String, description: String) {
        created[id] = issue(id: id, title: title)
        created[id]?["description"] = description
    }

    private func issue(id: String, title: String) -> [String: Any] {
        ["id": id, "identifier": "EWA-\(created.count + 1)", "title": title, "description": "Fixture requirements",
         "priority": 0, "url": "https://linear.app/kmsh-dev/issue/EWA-\(created.count + 1)",
         "state": ["name": "Todo", "type": "unstarted"],
         "project": ["id": ServiceScope.linearProjectID], "team": ["id": ServiceScope.linearTeamID]]
    }

    private func result(_ object: Any) throws -> ServiceHTTPResponse {
        ServiceHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), statusCode: 200)
    }
}

private func serviceRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw serviceFailure(message) }
}

private func serviceFailure(_ message: String) -> NSError {
    NSError(domain: "ServiceConnectionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

@MainActor
private func checkPublicationStopsOnPlanChange(in directory: URL) async throws {
    // Exercise success, lost-response recovery, and a UUID already holding older remote content.
    for (loseResponse, olderRemoteContent) in [(false, false), (true, false), (true, true)] {
        let journal = ServiceCheckJournal()
        let transport = ServiceCheckTransport(journal: journal)
        let connections = ServiceConnections(credentialStore: MemoryConnectionCredentials(journal: journal), transport: transport)
        try serviceRequire(await connections.connectLinear(token: "fixture-linear"), "Race fixture connects")
        let first = WorkTask(id: "first", title: "Original first assignment", owner: .interface,
                             paths: ["Apps/First.swift"], acceptance: ["First behavior verified"],
                             dependencies: [], handoff: "Share first result")
        let second = WorkTask(id: "second", title: "Original second assignment", owner: .quality,
                              paths: ["Tests/Second.swift"], acceptance: ["Second behavior verified"],
                              dependencies: [], handoff: "Share second result")
        let replacement = WorkPlan(summary: "Revised assignments", tasks: [
            WorkTask(id: "replacement", title: "Revised work", owner: .interface,
                     paths: ["Apps/Revised.swift"], acceptance: ["Revised behavior verified"],
                     dependencies: [], handoff: "Share revised result")
        ])
        var workspace = Workspace()
        let outcomeID = try workspace.recordOutcome("Change assignments while publication is running")
        try workspace.attach(WorkPlan(summary: "Original assignments", tasks: [first, second]), to: outcomeID)
        let repository = WorkspaceRepository(url: directory.appendingPathComponent("publication-race-\(loseResponse)-\(olderRemoteContent).json"))
        try await repository.save(workspace)
        let store = StudioStore(repository: repository, usesOnDeviceModel: true,
                                planner: { _, _ in PlanningResult(plan: replacement, questions: []) })
        await store.load()
        let captured = store.workspace.outcomes[0]
        if olderRemoteContent {
            let reserved = try await store.prepareIssuePublication(outcomeID: outcomeID, task: first)
            transport.seedIssue(id: reserved.issueID.uuidString.lowercased(), title: "Earlier plan assignment",
                                description: "Earlier requirements that were never updated")
        }
        transport.pauseNextCreateResponse = true
        transport.loseNextCreateResponse = loseResponse
        let publishing = Task { await connections.publishPlan(for: captured, store: store) }
        defer { transport.resumeCreateResponse() }
        try await waitForServiceCheck("Create request pauses") { transport.createResponseIsPaused }
        try serviceRequire(store.send("Replace these assignments", to: outcomeID),
                           "User can continue the conversation during publication")
        try await waitForServiceCheck("New assignments replace the captured plan") {
            store.workspace.outcomes[0].plan == replacement && !store.isPlanning
        }
        transport.resumeCreateResponse()
        await publishing.value
        try serviceRequire(transport.createAttempts == 1 && transport.updateAttempts == 0 && transport.created.count == 1,
                           "Changed plan stops remaining creates and recovery updates")
        let saved = try await repository.load()
        let receipt = saved.issueBinding(outcomeID: outcomeID, taskID: first.id)
        if olderRemoteContent {
            try serviceRequire(receipt != nil && receipt?.identifier == nil && receipt?.publishedTask == nil,
                               "Finding older content by reserved UUID does not claim the current snapshot was published")
        } else {
            try serviceRequire(receipt?.identifier == "EWA-1" && receipt?.publishedTask == first,
                               "In-flight create receipt remains durable with its original sent task")
        }
        try serviceRequire(saved.issueBinding(outcomeID: outcomeID, taskID: second.id) == nil &&
                           connections.publicationError == "Plan changed; review current assignments and publish again.",
                           "Unsent old task stays unpublished and current assignments are requested")
        let requestCount = transport.createAttempts + transport.updateAttempts
        await connections.publishPlan(for: captured, store: store)
        try serviceRequire(transport.createAttempts + transport.updateAttempts == requestCount,
                           "A stale direct publish cannot send mutations")
    }
    print("Publication race checks passed: plan replacement stops stale tasks and recovery updates while retaining completed receipts.")
}

@MainActor
private func waitForServiceCheck(_ message: String, condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw serviceFailure("Timed out: \(message)")
}

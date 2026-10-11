import EngineeringCore
import Foundation
import Observation
import Security

/// Credentials belong to this installed app's Keychain, never workspace JSON.
@MainActor
protocol ConnectionCredentialStore {
    func read(_ account: String) throws -> String?
    func write(_ value: String?, account: String) throws
}

@MainActor
struct SystemConnectionKeychain: ConnectionCredentialStore {
    func read(_ account: String) throws -> String? {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return value
    }

    func write(_ value: String?, account: String) throws {
        let query = identity(account)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    private func identity(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.kmsh.engineeringstudio.connections",
         kSecAttrAccount as String: account]
    }
    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "The connection credential could not be accessed securely (Keychain \(status))." }
    }
}

@MainActor @Observable
final class ServiceConnections {
    private(set) var repository: GitHubRepository?
    private(set) var pullRequests: [GitHubPullRequest] = []
    private(set) var workflowRuns: [GitHubWorkflowRun] = []
    private(set) var project: LinearProject?
    private(set) var issues: [LinearIssue] = []
    private(set) var githubStatus = "Not refreshed"
    private(set) var linearStatus = "Not connected"
    private(set) var githubError: String?
    private(set) var linearError: String?
    private(set) var refreshingGitHub = false
    private(set) var refreshingLinear = false
    private(set) var hasGitHubCredential = false
    private(set) var hasLinearCredential = false
    private(set) var githubUpdatedAt: Date?
    private(set) var linearUpdatedAt: Date?
    private(set) var githubTruncated = false
    private(set) var linearTruncated = false
    private(set) var publishingOutcomeID: UUID?
    private(set) var lastPublicationOutcomeID: UUID?
    private(set) var publicationStatus: String?
    private(set) var publicationError: String?
    @ObservationIgnored private var githubCredentialError: String?
    @ObservationIgnored private var githubToken: String?
    @ObservationIgnored private var linearToken: String?
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private let credentialStore: any ConnectionCredentialStore
    @ObservationIgnored private let transport: any ServiceHTTPTransport

    /// Constructing the model never reads Keychain, disk or the network.
    init(credentialStore: any ConnectionCredentialStore = SystemConnectionKeychain(),
         transport: any ServiceHTTPTransport = URLSessionServiceTransport()) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    /// Called by the actual app scene. Preview initialization does no I/O.
    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            githubToken = try credentialStore.read("github")
            hasGitHubCredential = githubToken != nil
        } catch {
            githubCredentialError = error.localizedDescription
            githubError = githubCredentialError
        }
        do {
            linearToken = try credentialStore.read("linear")
            hasLinearCredential = linearToken != nil
        } catch { linearError = error.localizedDescription }
        async let github: Void = refreshGitHub()
        async let linear: Void = refreshLinear()
        _ = await (github, linear)
    }

    @discardableResult func connectGitHub(token: String) async -> Bool {
        guard !refreshingGitHub else { return false }
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        do {
            // Verify scope before replacing an existing working credential.
            refreshingGitHub = true
            defer { refreshingGitHub = false }
            _ = try await GitHubService(token: value, transport: transport).repository()
            try credentialStore.write(value, account: "github")
            githubToken = value; hasGitHubCredential = true
            githubCredentialError = nil; githubError = nil
        } catch { githubError = error.localizedDescription; return false }
        await refreshGitHub()
        return true
    }

    @discardableResult func connectLinear(token: String) async -> Bool {
        guard !refreshingLinear, publishingOutcomeID == nil else { return false }
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        do {
            refreshingLinear = true
            defer { refreshingLinear = false }
            _ = try await LinearService(credential: .personalAPIKey(value), transport: transport).project()
            try credentialStore.write(value, account: "linear")
            linearToken = value; hasLinearCredential = true; linearError = nil
        } catch { linearError = error.localizedDescription; return false }
        await refreshLinear()
        return true
    }

    func refreshGitHub() async {
        guard !refreshingGitHub else { return }
        refreshingGitHub = true
        defer { refreshingGitHub = false }
        do {
            let client = GitHubService(token: githubToken, transport: transport)
            async let repositoryResult = client.repository()
            async let pullsResult = client.pullRequests()
            async let runsResult = client.workflowRuns()
            let (repo, pulls, runs) = try await (repositoryResult, pullsResult, runsResult)
            repository = repo; pullRequests = pulls.items; workflowRuns = runs.items
            githubTruncated = pulls.isTruncated || runs.isTruncated
            githubUpdatedAt = .now; githubError = githubCredentialError
            githubStatus = githubToken == nil
                ? (githubCredentialError == nil ? "Public repository access" : "Public access · Credential unavailable")
                : "Connected"
        } catch {
            githubError = error.localizedDescription
            githubStatus = githubUpdatedAt == nil ? "Could not connect" : "Refresh failed · Showing previous results"
        }
    }

    func refreshLinear() async {
        guard !refreshingLinear, let linearToken else { return }
        refreshingLinear = true
        defer { refreshingLinear = false }
        do {
            let client = LinearService(credential: .personalAPIKey(linearToken), transport: transport)
            async let projectResult = client.project()
            async let issuesResult = client.issues()
            let (newProject, newIssues) = try await (projectResult, issuesResult)
            project = newProject; issues = newIssues.items; linearTruncated = newIssues.isTruncated
            linearUpdatedAt = .now; linearError = nil; linearStatus = "Connected"
        } catch {
            linearError = error.localizedDescription
            linearStatus = linearUpdatedAt == nil ? "Could not connect" : "Refresh failed · Showing previous results"
        }
    }

    func disconnectGitHub() async {
        guard !refreshingGitHub else { return }
        do {
            try credentialStore.write(nil, account: "github")
            githubToken = nil; hasGitHubCredential = false; githubCredentialError = nil
            repository = nil; pullRequests = []; workflowRuns = []
            githubUpdatedAt = nil; githubTruncated = false; githubError = nil
            githubStatus = "Not refreshed"
            await refreshGitHub()
        } catch { githubError = error.localizedDescription }
    }

    func disconnectLinear() {
        guard !refreshingLinear, publishingOutcomeID == nil else { return }
        do {
            try credentialStore.write(nil, account: "linear")
            linearToken = nil; hasLinearCredential = false
            project = nil; issues = []; linearUpdatedAt = nil; linearTruncated = false
            linearError = nil; linearStatus = "Not connected"
            lastPublicationOutcomeID = nil; publicationStatus = nil; publicationError = nil
        } catch { linearError = error.localizedDescription }
    }

    func publishPlan(for outcome: Outcome, store: StudioStore) async {
        guard publishingOutcomeID == nil, let token = linearToken, let plan = outcome.plan else { return }
        publishingOutcomeID = outcome.id
        lastPublicationOutcomeID = outcome.id
        publicationError = nil; publicationStatus = "Publishing tasks…"
        defer { publishingOutcomeID = nil }
        let client = LinearService(credential: .personalAPIKey(token), transport: transport)
        do {
            try validatePublicationPlan(plan, outcomeID: outcome.id, store: store)
            for (index, task) in plan.tasks.enumerated() {
                try Task.checkCancellation()
                try validatePublicationPlan(plan, outcomeID: outcome.id, store: store)
                // No network mutation occurs before the reserved ID is durable.
                let binding = try await store.prepareIssuePublication(outcomeID: outcome.id, task: task)
                try validatePublicationPlan(plan, outcomeID: outcome.id, store: store)
                let description = issueDescription(task: task, outcome: outcome)
                let issue: LinearIssue
                if binding.identifier != nil {
                    issue = try await client.updateIssue(id: binding.issueID.uuidString, title: task.title, description: description)
                } else {
                    do {
                        issue = try await client.createIssue(title: task.title, description: description, id: binding.issueID)
                    } catch {
                        // A prior attempt may have reached Linear before its
                        // response or local receipt was lost. Reuse the same UUID.
                        guard let recovered = try? await client.issue(id: binding.issueID.uuidString) else { throw error }
                        // The create may already have completed remotely. Retain its
                        // receipt even if assignments changed while recovering it.
                        // A UUID alone does not prove this task snapshot was sent:
                        // the remote issue may belong to an earlier attempt's plan.
                        if recovered.title == task.title && recovered.description == description {
                            try await store.recordIssuePublication(outcomeID: outcome.id, task: task, issue: recovered)
                        }
                        try validatePublicationPlan(plan, outcomeID: outcome.id, store: store)
                        issue = try await client.updateIssue(id: recovered.id, title: task.title, description: description)
                    }
                }
                try await store.recordIssuePublication(outcomeID: outcome.id, task: task, issue: issue)
                // Never discard a completed request's receipt, but stop before
                // sending further tasks from a plan replaced during that request.
                try validatePublicationPlan(plan, outcomeID: outcome.id, store: store)
                publicationStatus = "Published \(index + 1) of \(plan.tasks.count) tasks"
            }
            await refreshLinear()
        } catch {
            publicationError = error.localizedDescription
            publicationStatus = "Publication paused · Saved receipts are retained"
        }
    }

    private func validatePublicationPlan(_ plan: WorkPlan, outcomeID: UUID, store: StudioStore) throws {
        guard store.workspace.outcomes.first(where: { $0.id == outcomeID })?.plan == plan else {
            throw PublicationError.planChanged
        }
        guard store.planningOutcomeID != outcomeID, !store.isQueuedForPlanning(outcomeID) else {
            throw PublicationError.planningInProgress
        }
    }

    private enum PublicationError: LocalizedError {
        case planChanged
        case planningInProgress
        var errorDescription: String? {
            switch self {
            case .planChanged: "Plan changed; review current assignments and publish again."
            case .planningInProgress: "Assignments are being prepared. Wait for planning to finish, then publish again."
            }
        }
    }

    private func issueDescription(task: WorkTask, outcome: Outcome) -> String {
        """
        ## Outcome
        \(outcome.text)

        ## Task ownership
        Specialty: \(task.owner.title)
        Repository: \(ServiceScope.repository)
        Outcome ID: \(outcome.id.uuidString)
        Task ID: \(task.id)

        ## Scope
        \(task.paths.map { "- `\($0)`" }.joined(separator: "\n"))

        ## Acceptance criteria
        \(task.acceptance.map { "- [ ] \($0)" }.joined(separator: "\n"))

        ## Dependencies
        \(task.dependencies.isEmpty ? "None" : task.dependencies.joined(separator: ", "))

        ## Handoff
        \(task.handoff)

        Published from Engineering Studio. No developer execution, test result or pull request is implied by ticket creation.
        """
    }
}

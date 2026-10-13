import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubService: Sendable {
    private let token: String?
    private let transport: any ServiceHTTPTransport
    private let maximumPages: Int

    public init(token: String? = nil, transport: any ServiceHTTPTransport = URLSessionServiceTransport(), maximumPages: Int = 3) {
        self.token = token
        self.transport = transport
        self.maximumPages = min(max(maximumPages, 1), 10)
    }

    public func repository() async throws -> GitHubRepository {
        let response = try await request(path: "")
        let repository: GitHubRepository = try ServiceValidation.decode(response.data)
        guard repository.fullName.lowercased() == ServiceScope.repository.lowercased() else { throw ServiceClientError.scopeMismatch }
        return repository
    }

    public func pullRequests() async throws -> ServicePage<GitHubPullRequest> {
        try await pages(path: "/pulls", query: [URLQueryItem(name: "state", value: "open")]) { try ServiceValidation.decode($0) }
    }

    public func workflowRuns() async throws -> ServicePage<GitHubWorkflowRun> {
        try await pages(path: "/actions/runs") { data in
            let envelope: WorkflowEnvelope = try ServiceValidation.decode(data)
            return envelope.workflowRuns
        }
    }

    public func checkRuns(commitSHA: String) async throws -> ServicePage<GitHubCheckRun> {
        guard [40, 64].contains(commitSHA.count), commitSHA.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw ServiceClientError.invalidInput("commit SHA")
        }
        return try await pages(path: "/commits/\(commitSHA)/check-runs", query: [URLQueryItem(name: "filter", value: "latest")]) { data in
            let envelope: CheckEnvelope = try ServiceValidation.decode(data)
            guard envelope.checkRuns.allSatisfy({ $0.headSHA.lowercased() == commitSHA.lowercased() }) else {
                throw ServiceClientError.scopeMismatch
            }
            return envelope.checkRuns
        }
    }

    /// Creates only a draft in the approved repository. No merge or publication API is exposed.
    /// Mutations are deliberately not automatically retried: an ambiguous network failure may already have applied.
    public func createDraftPullRequest(title: String, body: String, head: String, base: String) async throws -> GitHubPullRequest {
        guard let token, !token.isEmpty else { throw ServiceClientError.missingCredential }
        try ServiceValidation.validateTitle(title)
        try ServiceValidation.validateBranch(head)
        try ServiceValidation.validateBranch(base)
        guard head != base else { throw ServiceClientError.invalidInput("branch pair") }
        let payload = DraftRequest(title: title, body: body, head: head, base: base, draft: true)
        let response = try await request(path: "/pulls", method: "POST", body: JSONEncoder().encode(payload))
        let pullRequest: GitHubPullRequest = try ServiceValidation.decode(response.data)
        guard pullRequest.isDraft else { throw ServiceClientError.mutationRejected }
        return pullRequest
    }

    private func pages<Item: Sendable>(path: String, query: [URLQueryItem] = [],
                                      extract: (Data) throws -> [Item]) async throws -> ServicePage<Item> {
        var items: [Item] = []
        var hasNext = false
        for page in 1...maximumPages {
            try Task.checkCancellation()
            let response = try await request(path: path, query: query + [
                URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))
            ])
            items += try extract(response.data)
            // Never follow server-provided URLs: increment the page on our fixed endpoint instead.
            hasNext = response.headers["link"]?.split(separator: ",").contains(where: { $0.contains("rel=\"next\"") }) == true
            if !hasNext { break }
        }
        return ServicePage(items: items, isTruncated: hasNext)
    }

    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> ServiceHTTPResponse {
        var components = URLComponents(string: "https://api.github.com/repos/\(ServiceScope.repository)\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("EngineeringStudio", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token, !token.isEmpty {
            try ServiceValidation.validateCredential(token)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try ServiceValidation.checked(await transport.send(request))
    }

    private struct DraftRequest: Encodable { let title: String; let body: String; let head: String; let base: String; let draft: Bool }
    private struct WorkflowEnvelope: Decodable { let workflowRuns: [GitHubWorkflowRun]; enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" } }
    private struct CheckEnvelope: Decodable { let checkRuns: [GitHubCheckRun]; enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" } }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The app's approved service boundary. Credentials never select an endpoint or repository.
public enum ServiceScope {
    public static let repository = "kmshdev/foundation-models-utilities"
    public static let linearProjectID = "c655b4e0-e003-424a-a29a-3674e9a3983b"
    public static let linearTeamID = "1294bebc-4432-4532-8618-baa5794bdaec"
}

public struct ServicePage<Item: Sendable>: Sendable {
    public let items: [Item]
    /// True means the bounded request stopped before the service's final page.
    public let isTruncated: Bool
}

public enum ServiceClientError: Error, Sendable, Equatable, LocalizedError {
    case invalidInput(String)
    case missingCredential
    case http(status: Int, retryAfter: String?)
    case invalidResponse
    case graphQL
    case mutationRejected
    case scopeMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let field): "Invalid \(field)."
        case .missingCredential: "Connect an account before using this service."
        case .http(let status, let retryAfter):
            "Service returned HTTP \(status)." + (retryAfter.map { " Retry after \($0)." } ?? "")
        case .invalidResponse: "The service returned an unreadable response."
        case .graphQL: "Linear returned query errors. No partial result was accepted."
        case .mutationRejected: "The service did not confirm that the change was saved."
        case .scopeMismatch: "The service response does not match the configured scope."
        }
    }
}

public struct ServiceHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }
}

public protocol ServiceHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse
}

/// Ephemeral sessions avoid persisting authorization; refusing redirects prevents credential forwarding.
public final class URLSessionServiceTransport: ServiceHTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceClientError.invalidResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        return ServiceHTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GitHubRepository: Codable, Sendable, Identifiable {
    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, fullName = "full_name", defaultBranch = "default_branch", webURL = "html_url" }
}

public struct GitHubPullRequest: Codable, Sendable, Identifiable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let isDraft: Bool
    public let webURL: URL
    public let head: Head
    public var headSHA: String { head.sha }
    public struct Head: Codable, Sendable { public let sha: String }
    enum CodingKeys: String, CodingKey { case id, number, title, state, head, isDraft = "draft", webURL = "html_url" }
}

public struct GitHubWorkflowRun: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String?
    public let status: String
    public let conclusion: String?
    public let headSHA: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, headSHA = "head_sha", webURL = "html_url" }
}

/// A successful check is evidence for that named check only, never a total count of tests.
public struct GitHubCheckRun: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let headSHA: String
    public let webURL: URL?
    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, headSHA = "head_sha", webURL = "html_url" }
}

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
        let repository: GitHubRepository = try decode(response.data)
        guard repository.fullName.lowercased() == ServiceScope.repository.lowercased() else { throw ServiceClientError.scopeMismatch }
        return repository
    }

    public func pullRequests() async throws -> ServicePage<GitHubPullRequest> {
        try await pages(path: "/pulls", query: [URLQueryItem(name: "state", value: "open")]) { try decode($0) }
    }

    public func workflowRuns() async throws -> ServicePage<GitHubWorkflowRun> {
        try await pages(path: "/actions/runs") { data in
            let envelope: WorkflowEnvelope = try decode(data)
            return envelope.workflowRuns
        }
    }

    public func checkRuns(commitSHA: String) async throws -> ServicePage<GitHubCheckRun> {
        guard [40, 64].contains(commitSHA.count), commitSHA.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw ServiceClientError.invalidInput("commit SHA")
        }
        return try await pages(path: "/commits/\(commitSHA)/check-runs", query: [URLQueryItem(name: "filter", value: "latest")]) { data in
            let envelope: CheckEnvelope = try decode(data)
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
        try validateTitle(title)
        try validateBranch(head)
        try validateBranch(base)
        guard head != base else { throw ServiceClientError.invalidInput("branch pair") }
        let payload = DraftRequest(title: title, body: body, head: head, base: base, draft: true)
        let response = try await request(path: "/pulls", method: "POST", body: JSONEncoder().encode(payload))
        let pullRequest: GitHubPullRequest = try decode(response.data)
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
            try validateCredential(token)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try checked(await transport.send(request))
    }

    private struct DraftRequest: Encodable { let title: String; let body: String; let head: String; let base: String; let draft: Bool }
    private struct WorkflowEnvelope: Decodable { let workflowRuns: [GitHubWorkflowRun]; enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" } }
    private struct CheckEnvelope: Decodable { let checkRuns: [GitHubCheckRun]; enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" } }
}

public enum LinearCredential: Sendable {
    case personalAPIKey(String)
    case oauthToken(String)

    fileprivate var authorization: String {
        get throws {
            switch self {
            case .personalAPIKey(let key): try validateCredential(key); return key
            case .oauthToken(let token): try validateCredential(token); return "Bearer \(token)"
            }
        }
    }
}

public struct LinearProject: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, name, webURL = "url" }
}

public struct LinearIssue: Codable, Sendable, Identifiable {
    public let id: String
    public let identifier: String
    public let title: String
    public let description: String?
    public let priority: Int
    public let state: State
    public let webURL: URL
    public struct State: Codable, Sendable { public let name: String; public let type: String }
    enum CodingKeys: String, CodingKey { case id, identifier, title, description, priority, state, webURL = "url" }
}

public struct LinearService: Sendable {
    private let credential: LinearCredential
    private let transport: any ServiceHTTPTransport
    private let maximumPages: Int

    public init(credential: LinearCredential, transport: any ServiceHTTPTransport = URLSessionServiceTransport(), maximumPages: Int = 3) {
        self.credential = credential
        self.transport = transport
        self.maximumPages = min(max(maximumPages, 1), 10)
    }

    public func project() async throws -> LinearProject {
        let result: ProjectPayload = try await query("query StudioProject($id: String!) { project(id: $id) { id name url } }", variables: ["id": ServiceScope.linearProjectID])
        guard result.project.id == ServiceScope.linearProjectID else { throw ServiceClientError.scopeMismatch }
        return result.project
    }

    public func issues() async throws -> ServicePage<LinearIssue> {
        var items: [LinearIssue] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var hasNext = false
        for _ in 0..<maximumPages {
            try Task.checkCancellation()
            var variables = ["id": ServiceScope.linearProjectID]
            if let cursor { variables["after"] = cursor }
            let result: IssuesPayload = try await query("""
                query StudioIssues($id: String!, $after: String) {
                  project(id: $id) { id issues(first: 100, after: $after, orderBy: updatedAt) {
                    nodes { \(Self.issueFields) }
                    pageInfo { hasNextPage endCursor }
                  } }
                }
                """, variables: variables)
            guard result.project.id == ServiceScope.linearProjectID else { throw ServiceClientError.scopeMismatch }
            items += result.project.issues.nodes
            hasNext = result.project.issues.pageInfo.hasNextPage
            if !hasNext { break }
            guard let next = result.project.issues.pageInfo.endCursor, !next.isEmpty, seenCursors.insert(next).inserted else {
                throw ServiceClientError.invalidResponse
            }
            cursor = next
        }
        return ServicePage(items: items, isTruncated: hasNext)
    }

    /// Explicitly scoped to the approved project and team. No automatic mutation retries.
    public func createIssue(title: String, description: String, priority: Int = 0, id: UUID? = nil) async throws -> LinearIssue {
        try validateTitle(title)
        guard (0...4).contains(priority) else { throw ServiceClientError.invalidInput("priority") }
        if let id {
            let bytes = id.uuid
            guard bytes.6 >> 4 == 4, bytes.8 >> 6 == 2 else { throw ServiceClientError.invalidInput("issue UUID v4") }
        }
        // Official Linear schema supports a caller-reserved UUID v4. Persist it before sending.
        // https://github.com/linear/linear/blob/master/packages/sdk/src/schema.graphql
        let input = IssueInput(title: title, description: description, priority: priority,
                               teamId: ServiceScope.linearTeamID, projectId: ServiceScope.linearProjectID,
                               id: id?.uuidString.lowercased())
        let result: CreatePayload = try await query("""
            mutation StudioCreateIssue($input: IssueCreateInput!) {
              issueCreate(input: $input) { success issue { \(Self.issueFields) project { id } team { id } } }
            }
            """, variables: CreateVariables(input: input))
        guard result.issueCreate.success, let issue = result.issueCreate.issue else { throw ServiceClientError.mutationRejected }
        try validateScope(issue)
        if let id, issue.value.id.lowercased() != id.uuidString.lowercased() { throw ServiceClientError.scopeMismatch }
        return issue.value
    }

    /// Returns nil only for an explicit null issue without GraphQL errors. Permission, transport,
    /// and query errors are never interpreted as absence or as permission to create another issue.
    public func issue(id: String) async throws -> LinearIssue? {
        try validateIssueIdentifier(id)
        let result: IssuePayload = try await query("""
            query StudioIssue($id: String!) {
              issue(id: $id) { \(Self.issueFields) project { id } team { id } }
            }
            """, variables: ["id": id])
        guard let issue = result.issue else { return nil }
        try validateScope(issue)
        guard issue.value.id.caseInsensitiveCompare(id) == .orderedSame ||
              issue.value.identifier.caseInsensitiveCompare(id) == .orderedSame else { throw ServiceClientError.scopeMismatch }
        return issue.value
    }

    /// Resolve and validate scope before editing; validate the receipt again after the mutation.
    /// No project/team move is available through this API. Updates are not automatically retried.
    public func updateIssue(id: String, title: String, description: String) async throws -> LinearIssue {
        try validateTitle(title)
        guard let existing = try await issue(id: id) else { throw ServiceClientError.mutationRejected }
        let result: UpdatePayload = try await query("""
            mutation StudioUpdateIssue($id: String!, $input: IssueUpdateInput!) {
              issueUpdate(id: $id, input: $input) { success issue { \(Self.issueFields) project { id } team { id } } }
            }
            """, variables: UpdateVariables(id: existing.id, input: UpdateInput(title: title, description: description)))
        guard result.issueUpdate.success, let updated = result.issueUpdate.issue else { throw ServiceClientError.mutationRejected }
        try validateScope(updated)
        guard updated.value.id.caseInsensitiveCompare(existing.id) == .orderedSame else { throw ServiceClientError.scopeMismatch }
        return updated.value
    }

    private func validateScope(_ issue: ScopedIssue) throws {
        guard issue.project?.id == ServiceScope.linearProjectID, issue.team.id == ServiceScope.linearTeamID else {
            throw ServiceClientError.scopeMismatch
        }
    }

    private func query<Result: Decodable, Variables: Encodable>(_ query: String, variables: Variables) async throws -> Result {
        var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(try credential.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(QueryRequest(query: query, variables: variables))
        let response = try checked(await transport.send(request))
        // Inspect errors before decoding required data: GraphQL can return partial data alongside errors.
        let errors: ErrorEnvelope = try decode(response.data)
        guard errors.errors?.isEmpty != false else { throw ServiceClientError.graphQL }
        let envelope: DataEnvelope<Result> = try decode(response.data)
        guard let data = envelope.data else { throw ServiceClientError.invalidResponse }
        return data
    }

    private static let issueFields = "id identifier title description priority url state { name type }"
    private struct QueryRequest<Variables: Encodable>: Encodable { let query: String; let variables: Variables }
    private struct ErrorEnvelope: Decodable { let errors: [QueryError]? }
    private struct QueryError: Decodable { let message: String }
    private struct DataEnvelope<Value: Decodable>: Decodable { let data: Value? }
    private struct ProjectPayload: Decodable { let project: LinearProject }
    private struct IssuesPayload: Decodable { let project: ProjectIssues }
    private struct ProjectIssues: Decodable { let id: String; let issues: IssueConnection }
    private struct IssueConnection: Decodable { let nodes: [LinearIssue]; let pageInfo: PageInfo }
    private struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
    private struct IssueInput: Encodable { let title: String; let description: String; let priority: Int; let teamId: String; let projectId: String; let id: String? }
    private struct CreateVariables: Encodable { let input: IssueInput }
    private struct IssuePayload: Decodable {
        let issue: ScopedIssue?
        enum CodingKeys: String, CodingKey { case issue }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // decodeIfPresent would also accept a missing field as absence; require explicit null.
            issue = try container.decode(ScopedIssue?.self, forKey: .issue)
        }
    }
    private struct UpdateInput: Encodable { let title: String; let description: String }
    private struct UpdateVariables: Encodable { let id: String; let input: UpdateInput }
    private struct UpdatePayload: Decodable { let issueUpdate: CreatedIssue }
    private struct CreatePayload: Decodable { let issueCreate: CreatedIssue }
    private struct CreatedIssue: Decodable { let success: Bool; let issue: ScopedIssue? }
    private struct Identifier: Decodable { let id: String }
    private struct ScopedIssue: Decodable {
        let value: LinearIssue
        let project: Identifier?
        let team: Identifier
        enum CodingKeys: String, CodingKey { case project, team }
        init(from decoder: any Decoder) throws {
            value = try LinearIssue(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            project = try container.decodeIfPresent(Identifier.self, forKey: .project)
            team = try container.decode(Identifier.self, forKey: .team)
        }
    }
}

private func checked(_ response: ServiceHTTPResponse) throws -> ServiceHTTPResponse {
    guard (200..<300).contains(response.statusCode) else {
        throw ServiceClientError.http(status: response.statusCode, retryAfter: response.headers["retry-after"])
    }
    return response
}

private func decode<Value: Decodable>(_ data: Data) throws -> Value {
    do { return try JSONDecoder().decode(Value.self, from: data) }
    catch { throw ServiceClientError.invalidResponse }
}

private func validateCredential(_ value: String) throws {
    guard !value.isEmpty else { throw ServiceClientError.missingCredential }
    guard !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map({ $0 < 32 || $0 == 127 }) == true }) else {
        throw ServiceClientError.invalidInput("credential")
    }
}

private func validateTitle(_ title: String) throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 255 else {
        throw ServiceClientError.invalidInput("title")
    }
}

private func validateBranch(_ branch: String) throws {
    let invalidCharacters = CharacterSet(charactersIn: " ~^:?*[\\").union(.controlCharacters)
    guard !branch.isEmpty, branch != "@", !branch.hasPrefix("/"), !branch.hasSuffix("/"), !branch.hasSuffix("."),
          !branch.contains(".."), !branch.contains("@{"), !branch.contains("//"),
          branch.rangeOfCharacter(from: invalidCharacters) == nil,
          branch.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }) else {
        throw ServiceClientError.invalidInput("branch")
    }
}

private func validateIssueIdentifier(_ id: String) throws {
    guard UUID(uuidString: id) != nil || id.range(of: "^[A-Za-z][A-Za-z0-9]*-[0-9]+$", options: .regularExpression) != nil else {
        throw ServiceClientError.invalidInput("issue identifier")
    }
}

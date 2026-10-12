import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        try ServiceValidation.validateTitle(title)
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
        try ServiceValidation.validateIssueIdentifier(id)
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
        try ServiceValidation.validateTitle(title)
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
        request.setValue(try authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(QueryRequest(query: query, variables: variables))
        let response = try ServiceValidation.checked(await transport.send(request))
        // Inspect errors before decoding required data: GraphQL can return partial data alongside errors.
        let errors: ErrorEnvelope = try ServiceValidation.decode(response.data)
        guard errors.errors?.isEmpty != false else { throw ServiceClientError.graphQL }
        let envelope: DataEnvelope<Result> = try ServiceValidation.decode(response.data)
        guard let data = envelope.data else { throw ServiceClientError.invalidResponse }
        return data
    }

    private func authorizationHeader() throws -> String {
        switch credential {
        case .personalAPIKey(let value):
            try ServiceValidation.validateCredential(value)
            return value
        case .oauthToken(let value):
            try ServiceValidation.validateCredential(value)
            return "Bearer \(value)"
        }
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

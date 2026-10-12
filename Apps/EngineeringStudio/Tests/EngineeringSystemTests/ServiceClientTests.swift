import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import EngineeringCore
@testable import EngineeringServices

private actor RecordingTransport: ServiceHTTPTransport {
    private var responses: [ServiceHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [ServiceHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> ServiceHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ServiceClientError.invalidResponse }
        return responses.removeFirst()
    }
}

private func response(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> ServiceHTTPResponse {
    ServiceHTTPResponse(data: Data(json.utf8), statusCode: status, headers: headers)
}

private let repositoryJSON = #"{"id":1,"full_name":"kmshdev/foundation-models-utilities","default_branch":"swift-app","html_url":"https://github.com/kmshdev/foundation-models-utilities"}"#
private let pullRequestJSON = #"{"id":1,"number":4,"title":"Native app","state":"open","draft":true,"head":{"sha":"abc"},"html_url":"https://github.com/kmshdev/foundation-models-utilities/pull/4"}"#
private let issueJSON = #"{"id":"issue-1","identifier":"EWA-1","title":"Native navigation","description":null,"priority":2,"state":{"name":"Todo","type":"unstarted"},"url":"https://linear.app/kmsh-dev/issue/EWA-1"}"#

@Test func githubReadsPublicRepositoryWithoutCredential() async throws {
    let transport = RecordingTransport([response(repositoryJSON)])
    let result = try await GitHubService(transport: transport).repository()
    #expect(result.defaultBranch == "swift-app")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.github.com/repos/kmshdev/foundation-models-utilities")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.timeoutInterval == 30)
}

@Test func githubPaginationNeverFollowsUntrustedLinkAndReportsTruncation() async throws {
    let link = #"<https://attacker.invalid/steal>; rel="next""#
    let transport = RecordingTransport([
        response("[\(pullRequestJSON)]", headers: ["Link": link]),
        response("[]", headers: ["Link": link])
    ])
    let result = try await GitHubService(token: "test-token", transport: transport, maximumPages: 2).pullRequests()
    #expect(result.items.count == 1)
    #expect(result.isTruncated)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.url?.host == "api.github.com" })
    #expect(requests[1].url?.query?.contains("page=2") == true)
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
}

@Test func draftCreationEnforcesLocalBranchesAndDraftBody() async throws {
    let transport = RecordingTransport([response(pullRequestJSON, status: 201)])
    let service = GitHubService(token: "test-token", transport: transport)
    await #expect(throws: ServiceClientError.invalidInput("branch")) {
        try await service.createDraftPullRequest(title: "Change", body: "Details", head: "other:branch", base: "swift-app")
    }
    #expect(await transport.requests.isEmpty)
    let result = try await service.createDraftPullRequest(title: "Change", body: "Details", head: "feature/native", base: "swift-app")
    #expect(result.isDraft)
    let request = try #require(await transport.requests.first)
    let object = try requestBody(request)
    #expect(object["draft"] as? Bool == true)
    #expect(object["head"] as? String == "feature/native")
    #expect(request.httpMethod == "POST")
}

@Test func invalidInputNeverSendsCredential() async throws {
    let transport = RecordingTransport([])
    await #expect(throws: ServiceClientError.invalidInput("credential")) {
        try await GitHubService(token: "secret\nInjected: value", transport: transport).repository()
    }
    await #expect(throws: ServiceClientError.invalidInput("commit SHA")) {
        try await GitHubService(transport: transport).checkRuns(commitSHA: "../../other")
    }
    #expect(await transport.requests.isEmpty)
}

@Test func serviceHTTPAndParseErrorsAreExplicitWithoutBodyLeakage() async throws {
    let transport = RecordingTransport([
        response("sensitive server body", status: 429, headers: ["Retry-After": "60"]),
        response("<html>not JSON</html>"),
        response("redirect", status: 302)
    ])
    let service = GitHubService(transport: transport)
    await #expect(throws: ServiceClientError.http(status: 429, retryAfter: "60")) { try await service.repository() }
    await #expect(throws: ServiceClientError.invalidResponse) { try await service.repository() }
    await #expect(throws: ServiceClientError.http(status: 302, retryAfter: nil)) { try await service.repository() }
}

@Test func linearCredentialKindsAndProjectScope() async throws {
    let json = "{\"data\":{\"project\":{\"id\":\"\(ServiceScope.linearProjectID)\",\"name\":\"Engineering Workflow Automation\",\"url\":\"https://linear.app/kmsh-dev/project/engineering-workflow-automation-93f936d49f78\"}}}"
    let transport = RecordingTransport([response(json), response(json)])
    _ = try await LinearService(credential: .personalAPIKey("test-key"), transport: transport).project()
    _ = try await LinearService(credential: .oauthToken("test-oauth"), transport: transport).project()
    let requests = await transport.requests
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "test-key")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer test-oauth")
    #expect(requests.allSatisfy { $0.url?.absoluteString == "https://api.linear.app/graphql" })
    let body = try requestBody(requests[0])
    #expect((body["variables"] as? [String: String])?["id"] == ServiceScope.linearProjectID)
}

@Test func linearRejectsPartialGraphQLErrorsBeforeDecodingData() async throws {
    let transport = RecordingTransport([response(#"{"data":{"project":null},"errors":[{"message":"No permission","path":["project"]}]}"#)])
    await #expect(throws: ServiceClientError.graphQL) {
        try await LinearService(credential: .personalAPIKey("test-key"), transport: transport).project()
    }
}

private func issuePage(cursor: String, hasNext: Bool) -> String {
    "{\"data\":{\"project\":{\"id\":\"\(ServiceScope.linearProjectID)\",\"issues\":{\"nodes\":[\(issueJSON)],\"pageInfo\":{\"hasNextPage\":\(hasNext),\"endCursor\":\"\(cursor)\"}}}}}"
}

@Test func linearPaginationCarriesCursorAndStopsAtBound() async throws {
    let transport = RecordingTransport([response(issuePage(cursor: "cursor-a", hasNext: true)), response(issuePage(cursor: "cursor-b", hasNext: true))])
    let result = try await LinearService(credential: .personalAPIKey("test-key"), transport: transport, maximumPages: 2).issues()
    #expect(result.items.count == 2)
    #expect(result.isTruncated)
    let requests = await transport.requests
    let body = try requestBody(requests[1])
    #expect((body["variables"] as? [String: String])?["after"] == "cursor-a")
}

@Test func linearRepeatedCursorFailsInsteadOfLooping() async throws {
    let transport = RecordingTransport([response(issuePage(cursor: "same", hasNext: true)), response(issuePage(cursor: "same", hasNext: true))])
    await #expect(throws: ServiceClientError.invalidResponse) {
        try await LinearService(credential: .personalAPIKey("test-key"), transport: transport).issues()
    }
    #expect(await transport.requests.count == 2)
}

@Test func linearMutationHasFixedTeamAndProjectAndRequiresReceipt() async throws {
    let scopedIssue = String(issueJSON.dropLast()) + ",\"project\":{\"id\":\"\(ServiceScope.linearProjectID)\"},\"team\":{\"id\":\"\(ServiceScope.linearTeamID)\"}}"
    let transport = RecordingTransport([
        response("{\"data\":{\"issueCreate\":{\"success\":true,\"issue\":\(scopedIssue)}}}"),
        response(#"{"data":{"issueCreate":{"success":false,"issue":null}}}"#)
    ])
    let service = LinearService(credential: .personalAPIKey("test-key"), transport: transport)
    let result = try await service.createIssue(title: "Native navigation", description: "Acceptance", priority: 2)
    #expect(result.identifier == "EWA-1")
    let request = try #require(await transport.requests.first)
    let body = try requestBody(request)
    let variables = try #require(body["variables"] as? [String: Any])
    let input = try #require(variables["input"] as? [String: Any])
    #expect(input["teamId"] as? String == ServiceScope.linearTeamID)
    #expect(input["projectId"] as? String == ServiceScope.linearProjectID)
    await #expect(throws: ServiceClientError.mutationRejected) {
        try await service.createIssue(title: "Native navigation", description: "Acceptance")
    }
    #expect(await transport.requests.count == 2)
}

@Test func checkEvidenceIsBoundToRequestedCommit() async throws {
    let sha = String(repeating: "a", count: 40)
    let transport = RecordingTransport([response("{\"check_runs\":[{\"id\":1,\"name\":\"Build\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"\(String(repeating: "b", count: 40))\",\"html_url\":null}]}")])
    await #expect(throws: ServiceClientError.scopeMismatch) {
        try await GitHubService(transport: transport).checkRuns(commitSHA: sha)
    }
}

private func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func scopedIssueJSON(id: String = "issue-1", project: String = ServiceScope.linearProjectID) -> String {
    String(issueJSON.replacingOccurrences(of: "issue-1", with: id).dropLast()) +
        ",\"project\":{\"id\":\"\(project)\"},\"team\":{\"id\":\"\(ServiceScope.linearTeamID)\"}}"
}

@Test func linearReservedUUIDIsSentAndReceiptMustMatch() async throws {
    let id = UUID()
    let json = "{\"data\":{\"issueCreate\":{\"success\":true,\"issue\":\(scopedIssueJSON(id: id.uuidString.lowercased()))}}}"
    let transport = RecordingTransport([response(json), response(json)])
    let service = LinearService(credential: .personalAPIKey("test-key"), transport: transport)
    let result = try await service.createIssue(title: "Native navigation", description: "Acceptance", id: id)
    #expect(result.id == id.uuidString.lowercased())
    let request = try #require(await transport.requests.first)
    let body = try requestBody(request)
    let variables = try #require(body["variables"] as? [String: Any])
    let input = try #require(variables["input"] as? [String: Any])
    #expect(input["id"] as? String == id.uuidString.lowercased())
    await #expect(throws: ServiceClientError.scopeMismatch) {
        try await service.createIssue(title: "Native navigation", description: "Acceptance", id: UUID())
    }
    await #expect(throws: ServiceClientError.invalidInput("issue UUID v4")) {
        try await service.createIssue(title: "Native navigation", description: "Acceptance", id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
    #expect(await transport.requests.count == 2)
}

@Test func linearLookupOnlyAcceptsExplicitNullAsAbsent() async throws {
    let transport = RecordingTransport([
        response(#"{"data":{"issue":null}}"#),
        response(#"{"data":{}}"#),
        response(#"{"data":{"issue":null},"errors":[{"message":"Not found or forbidden"}]}"#)
    ])
    let service = LinearService(credential: .personalAPIKey("test-key"), transport: transport)
    #expect(try await service.issue(id: "EWA-1") == nil)
    await #expect(throws: ServiceClientError.invalidResponse) { try await service.issue(id: "EWA-1") }
    await #expect(throws: ServiceClientError.graphQL) { try await service.issue(id: "EWA-1") }
}

@Test func linearUpdateRejectsOutOfScopeBeforeMutation() async throws {
    let transport = RecordingTransport([response("{\"data\":{\"issue\":\(scopedIssueJSON(project: "another-project"))}}")])
    await #expect(throws: ServiceClientError.scopeMismatch) {
        try await LinearService(credential: .personalAPIKey("test-key"), transport: transport)
            .updateIssue(id: "EWA-1", title: "Update", description: "Description")
    }
    #expect(await transport.requests.count == 1)
}

@Test func linearUpdateUsesCanonicalIDAndVerifiesReceiptScope() async throws {
    let id = UUID().uuidString.lowercased()
    let issue = scopedIssueJSON(id: id)
    let transport = RecordingTransport([
        response("{\"data\":{\"issue\":\(issue)}}"),
        response("{\"data\":{\"issueUpdate\":{\"success\":true,\"issue\":\(issue)}}}"),
        response("{\"data\":{\"issue\":\(issue)}}"),
        response("{\"data\":{\"issueUpdate\":{\"success\":true,\"issue\":\(scopedIssueJSON(id: id, project: "other"))}}}")
    ])
    let service = LinearService(credential: .personalAPIKey("test-key"), transport: transport)
    _ = try await service.updateIssue(id: "EWA-1", title: "Update", description: "Description")
    let requests = await transport.requests
    let body = try requestBody(requests[1])
    let variables = try #require(body["variables"] as? [String: Any])
    #expect(variables["id"] as? String == id)
    let input = try #require(variables["input"] as? [String: Any])
    #expect(Set(input.keys) == ["title", "description"])
    await #expect(throws: ServiceClientError.scopeMismatch) {
        try await service.updateIssue(id: id, title: "Update", description: "Description")
    }
}

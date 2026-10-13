import EngineeringServices
import EngineeringCore
import Foundation

/// Read-only API fixtures prove MCP grant changes do not alter legacy adapter data.
struct ProviderCheckLegacyHTTP: ServiceHTTPTransport {
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        guard let url = request.url else { throw ProviderCheckFailure.assertion("Missing legacy fixture URL") }
        if url.host == "api.github.com" {
            if url.path.hasSuffix("/pulls") { return try response([]) }
            if url.path.hasSuffix("/actions/runs") { return try response(["workflow_runs": []]) }
            return try response(["id": 1, "full_name": ServiceScope.repository, "default_branch": "main",
                                 "html_url": "https://github.com/\(ServiceScope.repository)"])
        }
        guard url.absoluteString == "https://api.linear.app/graphql", let data = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = body["query"] as? String else {
            throw ProviderCheckFailure.assertion("Unexpected legacy adapter endpoint")
        }
        if query.contains("query StudioProject(") {
            return try response(["data": ["project": ["id": ServiceScope.linearProjectID,
                "name": "Engineering Workflow Automation", "url": "https://linear.app/fixture/project/engineering"]]])
        }
        if query.contains("query StudioIssues(") {
            return try response(["data": ["project": ["id": ServiceScope.linearProjectID,
                "issues": ["nodes": [], "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]]])
        }
        throw ProviderCheckFailure.assertion("OAuth regression fixtures cannot send API mutations")
    }

    private func response(_ value: Any) throws -> ServiceHTTPResponse {
        .init(data: try JSONSerialization.data(withJSONObject: value), statusCode: 200)
    }
}

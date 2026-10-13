import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the three initial public GitHub reads are supported; no network is opened.
actor StartupHTTPTransport: ServiceHTTPTransport {
    private(set) var requestCount = 0

    func send(_ request: URLRequest) throws -> ServiceHTTPResponse {
        requestCount += 1
        guard request.url?.host == "api.github.com", request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Authorization") == nil else {
            throw NSError(domain: "StartupHTTPTransport", code: 1)
        }
        let prefix = "/repos/\(ServiceScope.repository)"
        let response: String
        switch request.url?.path {
        case prefix:
            response = """
            {"id":1,"full_name":"\(ServiceScope.repository)","default_branch":"main","html_url":"https://github.com/\(ServiceScope.repository)"}
            """
        case prefix + "/pulls":
            response = "[]"
        case prefix + "/actions/runs":
            response = "{\"workflow_runs\":[]}"
        default:
            throw NSError(domain: "StartupHTTPTransport", code: 2)
        }
        return ServiceHTTPResponse(data: Data(response.utf8), statusCode: 200)
    }
}

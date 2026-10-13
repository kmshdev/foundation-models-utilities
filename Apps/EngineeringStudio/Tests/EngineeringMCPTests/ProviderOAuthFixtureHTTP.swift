import EngineeringMCP
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor ProviderOAuthFixtureHTTP: ProviderOAuthHTTPTransport {
    let provider: MCPProvider
    var expiresIn: Int
    var tokenScopes: String
    var refreshStatus = 200
    var refreshError: String?
    var omitRefreshedToken = false
    var invalidTokenEndpoint = false
    private(set) var requests: [URLRequest] = []
    private(set) var registrations = 0

    init(provider: MCPProvider, expiresIn: Int = 3_600) {
        self.provider = provider; self.expiresIn = expiresIn
        tokenScopes = provider == .linear ? "read" : ""
    }

    func setScopes(_ scopes: String) { tokenScopes = scopes }
    func setRefresh(status: Int, error: String? = nil, omitToken: Bool = false) {
        refreshStatus = status; refreshError = error; omitRefreshedToken = omitToken
    }
    func changeTokenEndpoint() { invalidTokenEndpoint = true }

    func send(_ request: URLRequest) async throws -> ProviderOAuthHTTPResponse {
        requests.append(request)
        let issuer = provider == .linear ? "https://mcp.linear.app" : "https://github.com/login/oauth"
        if request.url!.path.contains("oauth-protected-resource") {
            return try response(["resource": provider == .linear ? "https://mcp.linear.app/mcp/readonly"
                                 : "https://api.githubcopilot.com/mcp",
                                 "authorization_servers": [issuer],
                                 "scopes_supported": provider == .linear ? ["read"] : ["repo", "write:packages"]])
        }
        if request.url!.path.contains("oauth-authorization-server") {
            var body: [String: Any] = ["issuer": issuer, "authorization_endpoint": "\(issuer)/authorize",
                                      "token_endpoint": invalidTokenEndpoint ? "https://example.invalid/token"
                                        : provider == .linear ? "\(issuer)/token" : "\(issuer)/access_token",
                                      "code_challenge_methods_supported": ["S256"]]
            if provider == .linear {
                body["registration_endpoint"] = "\(issuer)/register"
                body["token_endpoint_auth_methods_supported"] = ["none"]
            }
            return try response(body)
        }
        if request.url!.path == "/register" {
            registrations += 1
            return try response(["client_id": "fixture-linear-client-\(registrations)",
                                 "token_endpoint_auth_method": "none"], status: 201)
        }
        let fields = Self.form(request)
        let isRefresh = fields["grant_type"] == "refresh_token"
        if isRefresh, let refreshError { return try response(["error": refreshError], status: refreshStatus) }
        if isRefresh, refreshStatus != 200 { return try response(["error": "temporarily_unavailable"], status: refreshStatus) }
        var body: [String: Any] = ["access_token": isRefresh ? "fixture-refreshed-access" : "fixture-access",
                                  "token_type": "Bearer", "expires_in": expiresIn, "scope": tokenScopes]
        if !isRefresh || !omitRefreshedToken { body["refresh_token"] = isRefresh ? "fixture-rotated-refresh" : "fixture-refresh" }
        return try response(body)
    }

    static func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: (URLComponents(string: "https://example.invalid/?\(body)")?.queryItems ?? [])
            .compactMap { item in item.value.map { (item.name, $0) } })
    }

    private func response(_ body: [String: Any], status: Int = 200) throws -> ProviderOAuthHTTPResponse {
        .init(statusCode: status, data: try JSONSerialization.data(withJSONObject: body))
    }
}

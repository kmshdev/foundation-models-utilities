import EngineeringMCP
import Foundation

/// All official-looking URLs are intercepted here; this fixture has no
/// URLSession and cannot contact GitHub, Linear or an MCP server.
actor ProviderCheckHTTP: ProviderOAuthHTTPTransport {
    let tokenGate = ProviderCheckGate()
    private var tokenLifetime = 3_600
    private var rejectToken = false
    private(set) var requestCount = 0
    private(set) var registrationCount = 0
    private(set) var tokenClientIDs: [String] = []
    private(set) var tokenGrantTypes: [String] = []

    var snapshot: (requests: Int, registrations: Int, clientIDs: [String], grants: [String]) {
        (requestCount, registrationCount, tokenClientIDs, tokenGrantTypes)
    }

    func setTokenLifetime(_ seconds: Int) { tokenLifetime = seconds }
    func setRejectToken(_ value: Bool) { rejectToken = value }

    func send(_ request: URLRequest) async throws -> ProviderOAuthHTTPResponse {
        requestCount += 1
        guard let url = request.url else { throw ProviderCheckFailure.assertion("Missing fixture URL") }
        if url.absoluteString == "https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp" {
            return try response(["resource": "https://api.githubcopilot.com/mcp/",
                                 "authorization_servers": ["https://github.com/login/oauth"]])
        }
        if url.absoluteString == "https://github.com/.well-known/oauth-authorization-server/login/oauth" {
            return try response([
                "issuer": "https://github.com/login/oauth", "authorization_endpoint": "https://github.com/login/oauth/authorize",
                "token_endpoint": "https://github.com/login/oauth/access_token", "response_types_supported": ["code"],
                "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["client_secret_post"]
            ])
        }
        if url.host == "mcp.linear.app", url.path.contains("oauth-protected-resource") {
            return try response([
                "resource": "https://mcp.linear.app/mcp/readonly",
                "authorization_servers": ["https://mcp.linear.app"], "scopes_supported": ["read"]
            ])
        }
        if url.host == "mcp.linear.app", url.path.contains("oauth-authorization-server") {
            return try response([
                "issuer": "https://mcp.linear.app", "authorization_endpoint": "https://mcp.linear.app/authorize",
                "token_endpoint": "https://mcp.linear.app/token", "registration_endpoint": "https://mcp.linear.app/register",
                "response_types_supported": ["code"], "grant_types_supported": ["authorization_code", "refresh_token"],
                "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["none"],
                "scopes_supported": ["read", "write"]
            ])
        }
        if url.host == "mcp.linear.app", url.path == "/register" {
            registrationCount += 1
            guard let data = request.httpBody,
                  let registration = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let redirects = registration["redirect_uris"] as? [String],
                  registration["token_endpoint_auth_method"] as? String == "none" else {
                throw ProviderCheckFailure.assertion("Linear registration must be public and bind the allocated callback")
            }
            return try response(["client_id": "isolated-linear-client", "redirect_uris": redirects,
                                 "token_endpoint_auth_method": "none"], status: 201)
        }
        if (url.host == "github.com" && url.path == "/login/oauth/access_token") ||
            (url.host == "mcp.linear.app" && url.path == "/token") {
            let form = URLComponents(string: "https://fixture.invalid/?" + String(decoding: request.httpBody ?? Data(), as: UTF8.self))?.queryItems ?? []
            guard let clientID = form.first(where: { $0.name == "client_id" })?.value,
                  let grantType = form.first(where: { $0.name == "grant_type" })?.value else {
                throw ProviderCheckFailure.assertion("Token exchange must identify its saved client and grant type")
            }
            tokenClientIDs.append(clientID)
            tokenGrantTypes.append(grantType)
            await tokenGate.waitIfSuspended()
            if rejectToken { return try response(["error": "invalid_grant"], status: 400) }
            let scope = url.host == "github.com" ? "" : "read"
            return try response(["access_token": "isolated-access-\(tokenGrantTypes.count)", "token_type": "bearer",
                                 "refresh_token": "isolated-refresh-\(tokenGrantTypes.count)", "scope": scope,
                                 "expires_in": tokenLifetime, "refresh_token_expires_in": 86_400])
        }
        throw ProviderCheckFailure.assertion("Unexpected OAuth fixture endpoint")
    }

    private func response(_ body: [String: Any], status: Int = 200) throws -> ProviderOAuthHTTPResponse {
        .init(statusCode: status, data: try JSONSerialization.data(withJSONObject: body))
    }
}

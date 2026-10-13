import Foundation
import MCP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native HTTP composition. This does not register an OAuth app or present authentication UI.
public enum EngineeringMCPHTTPFactory {
    /// The caller must supply a dedicated authorizer for this provider/account/transport.
    /// MCP OAuthAuthorizer must not be shared across transports (its upstream isolation contract).
    public static func oauth(policy: MCPToolPolicy, appVersion: String,
                             authorizer: OAuthAuthorizer, limits: MCPClientLimits = .init()) throws -> EngineeringMCPClient {
        let transport = makeTransport(identity: policy.identity, configuration: networkConfiguration(),
                                      authorizer: authorizer)
        return try EngineeringMCPClient(policy: policy, transport: transport,
                                        appVersion: appVersion, limits: limits)
    }

    /// For an externally acquired provider token, loaded synchronously from a secure store.
    /// Tokens remain in the transport and are excluded from application receipts/log messages.
    public static func token(policy: MCPToolPolicy, appVersion: String,
                             accessToken: @escaping @Sendable () -> String?,
                             limits: MCPClientLimits = .init()) throws -> EngineeringMCPClient {
        let transport = makeTransport(identity: policy.identity, configuration: networkConfiguration(),
                                      accessToken: accessToken)
        return try EngineeringMCPClient(policy: policy, transport: transport,
                                        appVersion: appVersion, limits: limits)
    }

    static func makeTransport(identity: MCPConnectionIdentity, configuration: URLSessionConfiguration,
                              authorizer: OAuthAuthorizer? = nil,
                              accessToken: (@Sendable () -> String?)? = nil) -> HTTPClientTransport {
        // SDK 0.12.1's optional GET listener waits for a session-ID signal even
        // after its timeout when a stateless server omits MCP-Session-Id.
        // `streaming: false` skips only that listener: send() still decodes JSON
        // and SSE POST responses. Reads refresh their catalog before invocation.
        HTTPClientTransport(endpoint: identity.endpoint, configuration: configuration,
                            streaming: false, authorizer: authorizer, requestModifier: { request in
            var request = readOnlyRequest(request, identity: identity)
            if request.url == identity.endpoint, let token = accessToken?(), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        })
    }

    /// Provider-supported read-only catalog mode supplements the local reviewed policy.
    /// GitHub's header does not change the token's authorization or repository grants.
    /// Linear uses its documented /mcp/readonly endpoint; discovery still honors the
    /// server's protected-resource metadata (which may identify the parent /mcp resource).
    static func readOnlyRequest(_ request: URLRequest, identity: MCPConnectionIdentity) -> URLRequest {
        var request = request
        if request.url == identity.endpoint, identity.provider == .github {
            request.setValue("true", forHTTPHeaderField: "X-MCP-Readonly")
        }
        return request
    }

    private static func networkConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return configuration
    }
}

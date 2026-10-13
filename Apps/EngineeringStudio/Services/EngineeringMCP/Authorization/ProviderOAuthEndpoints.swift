import Foundation

/// Metadata can select only these documented first-party authorization paths.
enum ProviderOAuthEndpoints {
    static let githubCallback = URL(string: "engineeringstudio://oauth/github")!
    static let linearCallbackPath = "/oauth/linear/callback"

    static func issuer(_ provider: MCPProvider) -> URL {
        switch provider {
        case .github: URL(string: "https://github.com/login/oauth")!
        case .linear: URL(string: "https://mcp.linear.app")!
        }
    }

    static func resourceMetadata(_ provider: MCPProvider) -> URL {
        switch provider {
        case .github: URL(string: "https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp")!
        case .linear: URL(string: "https://mcp.linear.app/.well-known/oauth-protected-resource/mcp/readonly")!
        }
    }

    static func serverMetadata(_ provider: MCPProvider) -> URL {
        switch provider {
        case .github: URL(string: "https://github.com/.well-known/oauth-authorization-server/login/oauth")!
        case .linear: URL(string: "https://mcp.linear.app/.well-known/oauth-authorization-server")!
        }
    }

    static func authorize(_ provider: MCPProvider) -> URL {
        switch provider {
        case .github: URL(string: "https://github.com/login/oauth/authorize")!
        case .linear: URL(string: "https://mcp.linear.app/authorize")!
        }
    }

    static func token(_ provider: MCPProvider) -> URL {
        switch provider {
        case .github: URL(string: "https://github.com/login/oauth/access_token")!
        case .linear: URL(string: "https://mcp.linear.app/token")!
        }
    }

    static let linearRegistration = URL(string: "https://mcp.linear.app/register")!

    static func accepts(resource: URL, provider: MCPProvider) -> Bool {
        let allowed: [String]
        switch provider {
        case .github: allowed = ["https://api.githubcopilot.com/mcp", "https://api.githubcopilot.com/mcp/"]
        case .linear: allowed = ["https://mcp.linear.app/mcp", "https://mcp.linear.app/mcp/readonly"]
        }
        return allowed.contains(resource.absoluteString)
    }

    static func validateRedirect(_ redirect: URL, provider: MCPProvider) throws {
        switch provider {
        case .github:
            guard redirect == githubCallback else { throw ProviderOAuthError.invalidCallback }
        case .linear:
            guard let value = URLComponents(url: redirect, resolvingAgainstBaseURL: false),
                  value.scheme == "http", value.host == "127.0.0.1", let port = value.port,
                  (1...65_535).contains(port), value.percentEncodedPath == linearCallbackPath,
                  value.user == nil, value.password == nil, value.query == nil, value.fragment == nil else {
                throw ProviderOAuthError.invalidCallback
            }
        }
    }
}

import Foundation
import Testing
@testable import EngineeringMCP

@Suite("Native provider OAuth contracts", .timeLimit(.minutes(1)))
struct ProviderOAuthSessionTests {
    private func fixture(_ provider: MCPProvider, expiresIn: Int = 3_600) throws
        -> (MCPConnectionIdentity, ProviderOAuthFixtureVault, ProviderOAuthFixtureHTTP, ProviderOAuthSession) {
        let identity = try MCPConnectionIdentity(provider: provider, accountID: UUID().uuidString)
        let vault = ProviderOAuthFixtureVault()
        let http = ProviderOAuthFixtureHTTP(provider: provider, expiresIn: expiresIn)
        return (identity, vault, http, ProviderOAuthSession(identity: identity, vault: vault, transport: http,
                                                         cryptography: ProviderOAuthFixtureCryptography()))
    }

    @Test("GitHub uses registered App PKCE and offline_access instead of broad MCP OAuth-App hints")
    func githubRegistrationAndScopes() async throws {
        let (_, _, http, session) = try fixture(.github)
        #expect(try await session.restore() == nil)
        try await session.configureGitHub(clientID: "fixture-github-app", clientSecret: "fixture-client-secret")
        #expect(try await session.githubClientID() == "fixture-github-app")
        let browser = ProviderOAuthFixtureBrowser()
        let receipt = try await session.authorize(using: browser)
        #expect(receipt.clientID == "fixture-github-app")
        #expect(receipt.scopes.isEmpty)
        let url = try #require(await browser.authorizationURL)
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(parameters.first { $0.name == "scope" }?.value == "offline_access")
        #expect(parameters.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(parameters.first { $0.name == "redirect_uri" }?.value == "engineeringstudio://oauth/github")
        let tokenRequest = try #require(await http.requests.last)
        let form = ProviderOAuthFixtureHTTP.form(tokenRequest)
        #expect(form["client_id"] == "fixture-github-app")
        #expect(form["client_secret"] == "fixture-client-secret")
        #expect(form["code_verifier"] == String(repeating: "v", count: 64))
        #expect(await http.registrations == 0)
    }

    @Test("Linear registers a native public client for the bound callback and requests only read")
    func linearNativeDCR() async throws {
        let (identity, vault, http, session) = try fixture(.linear)
        let browser = ProviderOAuthFixtureBrowser()
        let receipt = try await session.authorize(using: browser)
        #expect(receipt.identity == identity)
        #expect(receipt.scopes == ["read"])
        let requests = await http.requests
        let registration = try #require(requests.first { $0.url?.path == "/register" })
        let body = try #require(JSONSerialization.jsonObject(with: registration.httpBody!) as? [String: Any])
        #expect(body["application_type"] as? String == "native")
        #expect(body["token_endpoint_auth_method"] as? String == "none")
        #expect(body["scope"] as? String == "read")
        #expect(body["redirect_uris"] as? [String] == ["http://127.0.0.1:12301/oauth/linear/callback"])
        let raw = try #require(try await vault.read(.grant, for: identity))
        let stored = try JSONDecoder().decode(ProviderOAuthStoredGrant.self, from: raw)
        #expect(stored.clientID == receipt.clientID)
        #expect(stored.resource.absoluteString == "https://mcp.linear.app/mcp/readonly")
        #expect(stored.redirectURI.absoluteString == "http://127.0.0.1:12301/oauth/linear/callback")
    }

    @Test("Cold restart refresh binds the saved DCR client without new registration or browser consent")
    func refreshSavedClient() async throws {
        let (identity, vault, http, session) = try fixture(.linear, expiresIn: 1)
        let receipt = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        let restarted = ProviderOAuthSession(identity: identity, vault: vault, transport: http,
                                              cryptography: ProviderOAuthFixtureCryptography())
        #expect(try await restarted.restore()?.clientID == receipt.clientID)
        try await restarted.prepareForRead()
        #expect(await http.registrations == 1)
        let request = try #require(await http.requests.last)
        let form = ProviderOAuthFixtureHTTP.form(request)
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["client_id"] == receipt.clientID)
        #expect(form["refresh_token"] == "fixture-refresh")
        #expect(form["client_secret"] == nil)
        let data = try #require(try await vault.read(.grant, for: identity))
        let stored = try JSONDecoder().decode(ProviderOAuthStoredGrant.self, from: data)
        #expect(stored.refreshToken == "fixture-rotated-refresh")
        #expect(stored.pendingRefresh == nil)
    }

    @Test("A refresh response that omits a rotated token preserves the valid refresh credential")
    func omittedRefreshToken() async throws {
        let (_, _, http, session) = try fixture(.linear, expiresIn: 1)
        _ = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        await http.setRefresh(status: 200, omitToken: true)
        try await session.prepareForRead()
        try await session.prepareForRead()
        let refreshRequests = await http.requests.filter { ProviderOAuthFixtureHTTP.form($0)["grant_type"] == "refresh_token" }
        #expect(refreshRequests.count == 2)
        #expect(refreshRequests.allSatisfy { ProviderOAuthFixtureHTTP.form($0)["refresh_token"] == "fixture-refresh" })
    }

    @Test("Duplicate parameters and present malformed issuer callbacks never reach token exchange")
    func callbackParameters() async throws {
        let modes: [ProviderOAuthFixtureBrowser.Mode] = [.duplicateState, .valuelessIssuer, .emptyIssuer, .wrongIssuer]
        for mode in modes {
            let (_, _, http, session) = try fixture(.linear)
            await #expect(throws: ProviderOAuthError.invalidCallback) {
                try await session.authorize(using: ProviderOAuthFixtureBrowser(mode: mode))
            }
            #expect(await http.requests.allSatisfy { $0.url?.path != "/token" })
        }
    }

    @Test("Canceled delayed storage cannot replace an existing grant or resurrect after disconnect")
    func fencedStorage() async throws {
        let (identity, vault, http, session) = try fixture(.linear)
        _ = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        let before = try await vault.read(.grant, for: identity)
        await vault.blockNext(.grant)
        let authorization = Task { try await session.authorize(using: ProviderOAuthFixtureBrowser()) }
        await vault.waitForBlockedWrite()
        await session.cancel()
        await vault.releaseWrite()
        await #expect(throws: ProviderOAuthError.canceled) { try await authorization.value }
        #expect(try await vault.read(.grant, for: identity) == before)
        #expect(await http.registrations == 2)

        await vault.blockNext(.grant)
        let late = Task { try await session.authorize(using: ProviderOAuthFixtureBrowser()) }
        await vault.waitForBlockedWrite()
        try await session.disconnect()
        await vault.releaseWrite()
        await #expect(throws: ProviderOAuthError.canceled) { try await late.value }
        #expect(try await vault.read(.grant, for: identity) == nil)
    }

    @Test("Changing GitHub App configuration rejects the old grant without deleting protected data")
    func changedAppBinding() async throws {
        let (identity, vault, _, session) = try fixture(.github)
        try await session.configureGitHub(clientID: "fixture-app-one", clientSecret: "fixture-client-secret")
        _ = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        let before = try await vault.read(.grant, for: identity)
        try await session.configureGitHub(clientID: "fixture-app-two", clientSecret: "fixture-client-secret")
        await #expect(throws: ProviderOAuthError.configurationChanged) { try await session.restore() }
        #expect(try await vault.read(.grant, for: identity) == before)
        #expect(try await session.githubClientID() == "fixture-app-two")
    }

    @Test("Broader Linear grants and substituted metadata endpoints cannot replace an active connection")
    func scopeAndEndpointRejection() async throws {
        let (identity, vault, http, session) = try fixture(.linear)
        _ = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        let before = try await vault.read(.grant, for: identity)
        await http.setScopes("read write")
        await #expect(throws: ProviderOAuthError.scopeRejected) {
            try await session.authorize(using: ProviderOAuthFixtureBrowser())
        }
        #expect(try await vault.read(.grant, for: identity) == before)
        await http.changeTokenEndpoint()
        await #expect(throws: ProviderOAuthError.invalidMetadata) {
            try await session.authorize(using: ProviderOAuthFixtureBrowser())
        }
        #expect(try await vault.read(.grant, for: identity) == before)
    }

    @Test("OAuth invalid_grant is distinct from throttling even when returned as HTTP200")
    func refreshErrorClassification() async throws {
        let (_, _, http, session) = try fixture(.linear, expiresIn: 1)
        _ = try await session.authorize(using: ProviderOAuthFixtureBrowser())
        await http.setRefresh(status: 200, error: "invalid_grant")
        await #expect(throws: ProviderOAuthError.refreshExpired) { try await session.prepareForRead() }

        let (_, _, limitedHTTP, limitedSession) = try fixture(.linear, expiresIn: 1)
        _ = try await limitedSession.authorize(using: ProviderOAuthFixtureBrowser())
        await limitedHTTP.setRefresh(status: 429)
        await #expect(throws: ProviderOAuthError.networkUnavailable) { try await limitedSession.prepareForRead() }
    }

    @Test("Loopback rejects wrong Host, bodies and duplicate parameters before accepting the pending callback")
    func loopbackHTTPContract() throws {
        let target = "/oauth/linear/callback?code=fixture&state=pending"
        let valid = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:12345\r\n\r\n"
        let accepted = try ProviderOAuthLoopbackRequest.callbackURL(header: Data(valid.utf8), port: 12345, expectedState: "pending")
        #expect(accepted.host == "127.0.0.1")
        let invalid = [
            valid.replacingOccurrences(of: "Host: 127.0.0.1:12345", with: "Host: example.invalid"),
            valid.replacingOccurrences(of: " HTTP/1.1", with: "&state=pending HTTP/1.1"),
            valid.replacingOccurrences(of: "Host:", with: "Content-Length: 1\r\nHost:"),
            valid.replacingOccurrences(of: "/oauth/linear/callback", with: "/wrong"),
            valid.replacingOccurrences(of: "state=pending", with: "state=wrong")
        ]
        for request in invalid {
            #expect(throws: ProviderOAuthError.invalidCallback) {
                try ProviderOAuthLoopbackRequest.callbackURL(header: Data(request.utf8), port: 12345, expectedState: "pending")
            }
        }
    }
}

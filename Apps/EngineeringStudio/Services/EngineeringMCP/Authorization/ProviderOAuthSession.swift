import Foundation
import MCP
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App-owned OAuth lifecycle; the SDK remains the MCP protocol client.
/// A slot is local storage identity, never a claim about the signed-in person.
public actor ProviderOAuthSession {
    public let identity: MCPConnectionIdentity
    private let vault: any ProviderOAuthVault
    private let transport: any ProviderOAuthHTTPTransport
    private let cryptography: any ProviderOAuthCryptography
    private let tokenCache = ProviderOAuthTokenCache()
    private var configuration: ProviderOAuthClientConfiguration?
    private var grant: ProviderOAuthStoredGrant?
    private var loaded = false
    private var operation: ProviderOAuthOperation?
    private var cancelWork: (@Sendable () -> Void)?
    private var browser: (value: any ProviderOAuthBrowser, attemptID: UUID)?
    private var client: EngineeringMCPClient?

    public init(identity: MCPConnectionIdentity, vault: any ProviderOAuthVault,
                transport: any ProviderOAuthHTTPTransport = ProviderOAuthURLSessionTransport(),
                cryptography: any ProviderOAuthCryptography = ProviderOAuthSDKCryptography()) {
        self.identity = identity
        self.vault = vault
        self.transport = transport
        self.cryptography = cryptography
    }

    public func restore() async throws -> ProviderOAuthAuthorizationReceipt? {
        try await run { session, operation in try await session.restore(operation).map(\.receipt) }
    }

    /// Safe registration metadata is available even before a user grant exists.
    public func githubClientID() async throws -> String? {
        guard identity.provider == .github else { return nil }
        return try await run { session, operation in
            let value: ProviderOAuthClientConfiguration? = try await session.read(.configuration, operation)
            try session.check(operation)
            return value?.clientID
        }
    }

    /// Credentials are device-protected configuration, not source, workspace JSON or CI secrets.
    public func configureGitHub(clientID: String, clientSecret: String) async throws {
        guard identity.provider == .github, Self.validIdentifier(clientID),
              Self.validSecret(clientSecret) else { throw ProviderOAuthError.notConfigured }
        try await run { session, operation in
            let value = ProviderOAuthClientConfiguration(clientID: clientID, clientSecret: clientSecret)
            try await session.write(value, record: .configuration, operation)
            try session.check(operation)
            session.configuration = value
            session.tokenCache.replace(with: nil)
            let oldClient = session.client; session.client = nil
            await oldClient?.disconnect()
            try session.check(operation)
        }
    }

    /// Browser consent runs before any bounded MCP RPC begins. Existing grants survive failed attempts.
    public func authorize(using browser: any ProviderOAuthBrowser) async throws -> ProviderOAuthAuthorizationReceipt {
        try await run { session, operation in try await session.authorize(browser: browser, operation: operation) }
    }

    /// Silent refresh only. It never opens a browser or widens the grant.
    public func prepareForRead() async throws {
        try await run { session, operation in try await session.prepare(operation) }
    }

    public func makeReadOnlyClient(policy: MCPToolPolicy, appVersion: String,
                                   limits: MCPClientLimits = .init()) async throws -> EngineeringMCPClient {
        guard policy.identity == identity else { throw MCPClientError.invalidAccount }
        return try await run { session, operation in
            try await session.prepare(operation)
            let oldClient = session.client; session.client = nil
            await oldClient?.disconnect()
            try session.check(operation)
            let cache = session.tokenCache
            let value = try EngineeringMCPHTTPFactory.token(policy: policy, appVersion: appVersion,
                                                           accessToken: { cache.token() }, limits: limits)
            session.client = value
            return value
        }
    }

    /// Cancel the current attempt without deleting the previous complete grant.
    public func cancel() async { await cancelCurrent() }

    /// Termination closes network work but retains protected configuration and grants.
    public func close() async {
        await cancelCurrent()
        tokenCache.replace(with: nil)
        let previous = client; client = nil
        await previous?.disconnect()
    }

    /// Disconnect locally. This does not claim to revoke the provider-side authorization.
    public func disconnect() async throws {
        await close()
        try await run { session, operation in
            try await session.writeData(nil, record: .grant, operation)
            try session.check(operation)
            session.grant = nil; session.loaded = false
        }
    }

    // MARK: - Operation ownership

    private func run<Value: Sendable>(
        _ body: @escaping @Sendable (isolated ProviderOAuthSession, ProviderOAuthOperation) async throws -> Value
    ) async throws -> Value {
        guard operation == nil else { throw ProviderOAuthError.authorizationInProgress }
        let current = ProviderOAuthOperation()
        operation = current
        let task = Task { try await body(self, current) }
        cancelWork = { task.cancel() }
        return try await withTaskCancellationHandler {
            defer { finish(current) }
            do {
                let value = try await task.value
                try check(current)
                return value
            } catch {
                if !current.transaction.isActive || Task.isCancelled || error is CancellationError {
                    throw ProviderOAuthError.canceled
                }
                if let error = error as? ProviderOAuthError { throw error }
                if let error = error as? MCPClientError { throw error }
                throw ProviderOAuthError.networkUnavailable
            }
        } onCancel: { [weak self] in
            current.transaction.invalidate()
            task.cancel()
            Task { await self?.cancelCurrent(matching: current.id) }
        }
    }

    private func check(_ current: ProviderOAuthOperation) throws {
        guard operation?.id == current.id, current.transaction.isActive, !Task.isCancelled else {
            throw ProviderOAuthError.canceled
        }
    }

    private func finish(_ current: ProviderOAuthOperation) {
        guard operation?.id == current.id else { return }
        operation = nil; cancelWork = nil; browser = nil
    }

    private func cancelCurrent(matching id: UUID? = nil) async {
        guard let current = operation, id == nil || id == current.id else { return }
        current.transaction.invalidate()
        let cancel = cancelWork; cancelWork = nil
        let browser = self.browser; self.browser = nil
        operation = nil
        cancel?()
        if let browser { await browser.value.cancel(attemptID: browser.attemptID) }
    }

    // MARK: - Protected state

    private func restore(_ current: ProviderOAuthOperation) async throws -> ProviderOAuthStoredGrant? {
        let savedConfig: ProviderOAuthClientConfiguration? = try await read(.configuration, current)
        let savedGrant: ProviderOAuthStoredGrant? = try await read(.grant, current)
        try check(current)
        if let savedConfig {
            guard Self.validIdentifier(savedConfig.clientID), Self.validSecret(savedConfig.clientSecret) else {
                throw ProviderOAuthError.secureStorageUnavailable
            }
        }
        configuration = savedConfig
        if let savedGrant { try validate(savedGrant) }
        grant = savedGrant; loaded = true
        tokenCache.replace(with: savedGrant?.pendingRefresh == nil ? savedGrant : nil)
        return savedGrant
    }

    private func read<Value: Decodable & Sendable>(_ record: ProviderOAuthVaultRecord,
                                                   _ current: ProviderOAuthOperation) async throws -> Value? {
        do {
            let data = try await vault.read(record, for: identity)
            try check(current)
            guard let data else { return nil }
            guard data.count <= 65_536 else { throw ProviderOAuthError.secureStorageUnavailable }
            return try JSONDecoder().decode(Value.self, from: data)
        } catch let error as ProviderOAuthError { throw error }
        catch { throw ProviderOAuthError.secureStorageUnavailable }
    }

    private func write<Value: Encodable & Sendable>(_ value: Value, record: ProviderOAuthVaultRecord,
                                                    _ current: ProviderOAuthOperation) async throws {
        do { try await writeData(JSONEncoder().encode(value), record: record, current) }
        catch let error as ProviderOAuthError { throw error }
        catch { throw ProviderOAuthError.secureStorageUnavailable }
    }

    private func writeData(_ data: Data?, record: ProviderOAuthVaultRecord,
                           _ current: ProviderOAuthOperation) async throws {
        try check(current)
        do {
            try await vault.write(data, record: record, for: identity, transaction: current.transaction)
            try check(current)
        } catch let error as ProviderOAuthError { throw error }
        catch { throw ProviderOAuthError.secureStorageUnavailable }
    }

    private func validate(_ value: ProviderOAuthStoredGrant) throws {
        guard value.identity == identity, Self.validIdentifier(value.clientID), Self.validSecret(value.accessToken),
              ProviderOAuthEndpoints.accepts(resource: value.resource, provider: identity.provider),
              value.authorizationServer == ProviderOAuthEndpoints.issuer(identity.provider),
              value.tokenEndpoint == ProviderOAuthEndpoints.token(identity.provider) else {
            throw ProviderOAuthError.secureStorageUnavailable
        }
        try ProviderOAuthEndpoints.validateRedirect(value.redirectURI, provider: identity.provider)
        try validateScopes(value.scopes)
        if identity.provider == .github, configuration?.clientID != value.clientID {
            throw ProviderOAuthError.configurationChanged
        }
    }

    // MARK: - Browser authorization

    private func authorize(browser nativeBrowser: any ProviderOAuthBrowser,
                           operation current: ProviderOAuthOperation) async throws -> ProviderOAuthAuthorizationReceipt {
        // Load configuration separately so an old grant for another registered app does not block replacement.
        configuration = try await read(.configuration, current)
        if identity.provider == .github, configuration == nil { throw ProviderOAuthError.notConfigured }
        let (resource, metadata) = try await discover(current)
        let attempt = try await nativeBrowser.prepareCallback(for: identity.provider)
        do {
            try check(current)
            browser = (nativeBrowser, attempt.id)
            try ProviderOAuthEndpoints.validateRedirect(attempt.redirectURI, provider: identity.provider)
            let registration: ProviderOAuthRegistration
            switch identity.provider {
            case .github:
                guard let configuration else { throw ProviderOAuthError.notConfigured }
                registration = .init(clientID: configuration.clientID, redirectURI: attempt.redirectURI)
            case .linear:
                registration = try await register(redirect: attempt.redirectURI, current)
                // Persist the candidate separately; never overwrite the previous grant before consent/token success.
                try await write(registration, record: .pendingRegistration, current)
            }
            let verifier = try cryptography.randomToken()
            let state = try cryptography.randomToken()
            let challenge = try cryptography.challenge(for: verifier)
            guard (43...128).contains(verifier.count), !state.isEmpty, !challenge.isEmpty else {
                throw ProviderOAuthError.tokenRejected
            }
            let requestedScopes: Set<String> = identity.provider == .linear ? ["read"] : ["offline_access"]
            let authorizationURL = try OAuthAuthorizationCodeFlow().buildURL(
                authorizationEndpoint: metadata.authorizationEndpoint, resource: resource,
                redirectURI: registration.redirectURI, clientID: registration.clientID,
                codeChallenge: challenge, scopes: requestedScopes, state: state,
                scopeSerializer: DefaultOAuthScopeSelector())
            let callback = try await nativeBrowser.present(authorizationURL: authorizationURL, attempt: attempt)
            try check(current)
            let code = try ProviderOAuthCallbackValidation.code(from: callback, redirectURI: registration.redirectURI,
                                                               state: state, issuer: metadata.issuer)
            var parameters = ["grant_type": "authorization_code", "client_id": registration.clientID,
                              "code": code, "code_verifier": verifier,
                              "redirect_uri": registration.redirectURI.absoluteString,
                              "resource": resource.absoluteString]
            if identity.provider == .github { parameters["client_secret"] = configuration?.clientSecret }
            let response = try await token(parameters: parameters, current)
            let value = try makeGrant(response: response, registration: registration, resource: resource, previous: nil)
            try await write(value, record: .grant, current)
            try check(current)
            grant = value; loaded = true
            tokenCache.replace(with: value)
            await nativeBrowser.cancel(attemptID: attempt.id)
            if browser?.attemptID == attempt.id { browser = nil }
            return value.receipt
        } catch {
            await nativeBrowser.cancel(attemptID: attempt.id)
            if browser?.attemptID == attempt.id { browser = nil }
            throw error
        }
    }

    // MARK: - Discovery and registration

    private func discover(_ current: ProviderOAuthOperation) async throws -> (URL, ProviderOAuthServerMetadata) {
        let provider = identity.provider
        let protected: ProviderOAuthProtectedResource = try await get(ProviderOAuthEndpoints.resourceMetadata(provider), current)
        guard ProviderOAuthEndpoints.accepts(resource: protected.resource, provider: provider),
              protected.authorizationServers.contains(ProviderOAuthEndpoints.issuer(provider)) else {
            throw ProviderOAuthError.invalidMetadata
        }
        if provider == .linear, let scopes = protected.scopesSupported, !scopes.contains("read") {
            throw ProviderOAuthError.scopeRejected
        }
        let metadata: ProviderOAuthServerMetadata = try await get(ProviderOAuthEndpoints.serverMetadata(provider), current)
        guard metadata.issuer == ProviderOAuthEndpoints.issuer(provider),
              metadata.authorizationEndpoint == ProviderOAuthEndpoints.authorize(provider),
              metadata.tokenEndpoint == ProviderOAuthEndpoints.token(provider),
              metadata.codeChallengeMethodsSupported.contains("S256") else {
            throw ProviderOAuthError.invalidMetadata
        }
        if provider == .linear {
            guard metadata.registrationEndpoint == ProviderOAuthEndpoints.linearRegistration,
                  metadata.tokenEndpointAuthMethodsSupported?.contains("none") == true else {
                throw ProviderOAuthError.invalidMetadata
            }
        }
        return (protected.resource, metadata)
    }

    private func register(redirect: URL, _ current: ProviderOAuthOperation) async throws -> ProviderOAuthRegistration {
        var request = URLRequest(url: ProviderOAuthEndpoints.linearRegistration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Engineering Studio", "application_type": "native", "token_endpoint_auth_method": "none",
            "redirect_uris": [redirect.absoluteString], "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"], "scope": "read"
        ])
        let response = try await send(request, current)
        guard (200..<300).contains(response.statusCode),
              let value = try? JSONDecoder().decode(ProviderOAuthRegistrationResponse.self, from: response.data),
              Self.validIdentifier(value.clientID),
              value.tokenEndpointAuthMethod == nil || value.tokenEndpointAuthMethod == "none",
              value.redirectURIs == nil || value.redirectURIs?.contains(redirect.absoluteString) == true else {
            throw ProviderOAuthError.registrationFailed
        }
        return .init(clientID: value.clientID, redirectURI: redirect)
    }

    // MARK: - Refresh

    private func prepare(_ current: ProviderOAuthOperation) async throws {
        if !loaded { _ = try await restore(current) }
        guard var value = grant else { throw ProviderOAuthError.notAuthorized }
        try validate(value)
        if value.pendingRefresh == nil,
           value.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) ?? true {
            tokenCache.replace(with: value)
            return
        }
        tokenCache.replace(with: nil)
        guard let refresh = value.refreshToken,
              value.refreshExpiresAt.map({ $0 > Date().addingTimeInterval(30) }) ?? true else {
            throw ProviderOAuthError.refreshExpired
        }
        if let pending = value.pendingRefresh {
            // Linear explicitly documents a 30-minute recovery replay. GitHub does not.
            guard identity.provider == .linear, Date().timeIntervalSince(pending.startedAt) < 1_800 else {
                throw ProviderOAuthError.refreshExpired
            }
        } else {
            value.pendingRefresh = .init(token: refresh, startedAt: .now)
            try await write(value, record: .grant, current)
            grant = value
        }
        var parameters = ["grant_type": "refresh_token", "client_id": value.clientID,
                          "refresh_token": value.pendingRefresh?.token ?? refresh,
                          "resource": value.resource.absoluteString]
        if identity.provider == .github {
            guard let configuration, configuration.clientID == value.clientID else {
                throw ProviderOAuthError.configurationChanged
            }
            parameters["client_secret"] = configuration.clientSecret
        }
        let response = try await token(parameters: parameters, current)
        let updated = try makeGrant(response: response,
                                    registration: .init(clientID: value.clientID, redirectURI: value.redirectURI),
                                    resource: value.resource, previous: value)
        try await write(updated, record: .grant, current)
        try check(current)
        grant = updated
        tokenCache.replace(with: updated)
    }

    private func makeGrant(response: ProviderOAuthTokenResponse, registration: ProviderOAuthRegistration,
                           resource: URL, previous: ProviderOAuthStoredGrant?) throws -> ProviderOAuthStoredGrant {
        guard Self.validSecret(response.accessToken), response.tokenType.lowercased() == "bearer",
              response.expiresIn.map({ $0 > 0 && $0 <= 31_536_000 }) ?? true,
              response.refreshTokenExpiresIn.map({ $0 > 0 && $0 <= 31_536_000 }) ?? true,
              response.refreshToken.map(Self.validSecret) ?? true else { throw ProviderOAuthError.tokenRejected }
        let scopes = response.scope.map { Set($0.split(whereSeparator: \.isWhitespace).map(String.init)) }
            ?? previous?.scopes ?? (identity.provider == .linear ? ["read"] : [])
        try validateScopes(scopes)
        let now = Date()
        return .init(identity: identity, clientID: registration.clientID, redirectURI: registration.redirectURI,
                     resource: resource, authorizationServer: ProviderOAuthEndpoints.issuer(identity.provider),
                     tokenEndpoint: ProviderOAuthEndpoints.token(identity.provider), accessToken: response.accessToken,
                     scopes: scopes, expiresAt: response.expiresIn.map { now.addingTimeInterval(Double($0)) },
                     refreshToken: response.refreshToken ?? previous?.refreshToken,
                     refreshExpiresAt: response.refreshTokenExpiresIn.map { now.addingTimeInterval(Double($0)) }
                        ?? previous?.refreshExpiresAt, pendingRefresh: nil)
    }

    private func validateScopes(_ scopes: Set<String>) throws {
        let allowed: Set<String> = identity.provider == .linear ? ["read"] : ["offline_access"]
        guard scopes.isSubset(of: allowed), identity.provider != .linear || scopes.contains("read") else {
            throw ProviderOAuthError.scopeRejected
        }
    }

    // MARK: - Bounded HTTP

    private func get<Value: Decodable & Sendable>(_ url: URL,
                                                 _ current: ProviderOAuthOperation) async throws -> Value {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await send(request, current)
        guard (200..<300).contains(response.statusCode),
              let value = try? JSONDecoder().decode(Value.self, from: response.data) else {
            throw ProviderOAuthError.invalidMetadata
        }
        return value
    }

    private func token(parameters: [String: String],
                       _ current: ProviderOAuthOperation) async throws -> ProviderOAuthTokenResponse {
        var request = URLRequest(url: ProviderOAuthEndpoints.token(identity.provider))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(parameters.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        let response = try await send(request, current)
        if response.statusCode == 429 || (500..<600).contains(response.statusCode) {
            throw ProviderOAuthError.networkUnavailable
        }
        if let failure = try? JSONDecoder().decode(ProviderOAuthTokenErrorResponse.self, from: response.data),
           let name = failure.error {
            if parameters["grant_type"] == "refresh_token", name == "invalid_grant" {
                throw ProviderOAuthError.refreshExpired
            }
            if name == "access_denied" { throw ProviderOAuthError.authorizationDenied }
            throw ProviderOAuthError.tokenRejected
        }
        guard (200..<300).contains(response.statusCode),
              let value = try? JSONDecoder().decode(ProviderOAuthTokenResponse.self, from: response.data) else {
            throw ProviderOAuthError.tokenRejected
        }
        return value
    }

    private func send(_ request: URLRequest, _ current: ProviderOAuthOperation) async throws -> ProviderOAuthHTTPResponse {
        try check(current)
        let response = try await transport.send(request)
        try check(current)
        guard response.data.count <= 262_144 else { throw ProviderOAuthError.invalidMetadata }
        return response
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }

    private static func validSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384 && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }
}

import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Owns account identity, protected credential rotation and serialized persistence.
public actor ChatGPTSession: ChatGPTTokenProviding {
    private let vault: any ChatGPTCredentialVault
    private let transport: any ServiceHTTPTransport
    private let cryptography: any ChatGPTAuthorizationCryptography
    private let validator: ChatGPTIDTokenValidator
    private let clock: @Sendable () -> Date
    private var state: ChatGPTCredentialState?
    private var restoration: Task<ChatGPTCredentialState, any Error>?
    private var writeTail: Task<Void, any Error>?
    private var writeID: UUID?
    private var pending: ChatGPTAuthorizationAttempt?
    private var completingAttempt: UUID?
    private var generation = UUID()
    private var refresh: Task<String, any Error>?
    private var refreshID: UUID?
    private var discovery: Discovery?
    private var jwks: Data?
    private var keysFetchedAt: Date?

    public init(vault: any ChatGPTCredentialVault, transport: any ServiceHTTPTransport = URLSessionServiceTransport(),
                signatureVerifier: any ChatGPTJWTSignatureVerifying,
                authorizationCryptography: any ChatGPTAuthorizationCryptography,
                clock: @escaping @Sendable () -> Date = Date.init) {
        self.vault = vault; self.transport = transport; self.cryptography = authorizationCryptography
        self.validator = ChatGPTIDTokenValidator(verifier: signatureVerifier); self.clock = clock
    }

    public func restore() async throws {
        guard state == nil else { return }
        if let restoration {
            let value = try await restoration.value
            if state == nil { state = value }
            return
        }
        let task = Task { try await self.restoreState() }
        restoration = task
        defer { restoration = nil }
        let value = try await task.value
        if state == nil { state = value }
    }

    private func restoreState() async throws -> ChatGPTCredentialState {
        do {
            if let saved = try await vault.load() {
                guard saved.hostID.hasPrefix("urn:uuid:"), UUID(uuidString: String(saved.hostID.dropFirst(9))) != nil,
                      saved.pendingClientID.map(validClientID) ?? true,
                      Set(saved.registrations.map(\.clientID)).count == saved.registrations.count,
                      saved.registrations.allSatisfy({ validClientID($0.clientID) && $0.issuer == "https://auth.openai.com" && !$0.subject.isEmpty }) else { throw ChatGPTAuthenticationError.persistenceFailed }
                return saved
            }
            let value = ChatGPTCredentialState(hostID: "urn:uuid:\(UUID().uuidString.lowercased())")
            try await vault.save(value)
            return value
        } catch { throw ChatGPTAuthenticationError.persistenceFailed }
    }

    public func accounts() -> [ChatGPTAccount] { state?.registrations.map(\.account) ?? [] }
    public func activeAccount() -> ChatGPTAccount? { selectedRegistration()?.account }

    public func selectAccount(id: String) async throws {
        try await restore()
        if let refresh { _ = try? await refresh.value }
        guard var next = state, next.registrations.contains(where: { $0.clientID == id }) else { throw ChatGPTAuthenticationError.notSignedIn }
        cancelAuthorization(); refresh?.cancel(); refresh = nil; refreshID = nil
        let expectedGeneration = generation
        next.activeClientID = id
        try await persist(next)
        guard generation == expectedGeneration else { throw ChatGPTAuthenticationError.canceled }
        state = next
    }

    public func beginAuthorization(port: UInt16, accountID: String? = nil, enablePlanUsage: Bool = false) async throws -> ChatGPTAuthorizationAttempt {
        try await restore()
        if let refresh { _ = try? await refresh.value }
        guard pending == nil, completingAttempt == nil else { throw ChatGPTAuthenticationError.authorizationInProgress }
        guard port > 0, let state else { throw ChatGPTAuthenticationError.invalidCallback }
        let selected: ChatGPTRegistration?
        if let accountID {
            guard let value = state.registrations.first(where: { $0.clientID == accountID }) else { throw ChatGPTAuthenticationError.notSignedIn }
            selected = value
        } else { selected = nil }
        let verifier = try cryptography.randomToken(); let randomState = try cryptography.randomToken(); let nonce = try cryptography.randomToken()
        guard verifier.count >= 43, verifier.count <= 128, randomState.count >= 43, nonce.count >= 43 else { throw ChatGPTAuthenticationError.invalidTokenResponse }
        let requestClientID = selected?.clientID ?? state.pendingClientID
        let callback = URL(string: "http://127.0.0.1:\(port)/auth/callback")!
        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: requestClientID ?? "dynamic_agent_client"),
            URLQueryItem(name: "ext_agent_host_id", value: state.hostID), URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: callback.absoluteString),
            URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name: "resource", value: "https://api.openai.com/v1"), URLQueryItem(name: "state", value: randomState),
            URLQueryItem(name: "nonce", value: nonce), URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: try cryptography.challenge(for: verifier))]
        if requestClientID == nil { components.queryItems?.append(URLQueryItem(name: "agent_name_hint", value: "Engineering Studio")) }
        if let hint = selected?.tokens?.idToken { components.queryItems?.append(URLQueryItem(name: "id_token_hint", value: hint)) }
        if let email = selected?.email { components.queryItems?.append(URLQueryItem(name: "login_hint", value: email)) }
        if enablePlanUsage { components.queryItems?.append(URLQueryItem(name: "prompt", value: "consent")) }
        let value = ChatGPTAuthorizationAttempt(authorizationURL: components.url!, callbackURL: callback, expiresAt: clock().addingTimeInterval(300),
                                               id: UUID(), state: randomState, nonce: nonce, verifier: verifier, clientID: requestClientID)
        pending = value
        return value
    }

    public func cancelAuthorization() { pending = nil; completingAttempt = nil; generation = UUID() }

    public func completeAuthorization(callbackURL: URL) async throws -> ChatGPTAccount {
        guard let attempt = pending else { throw ChatGPTAuthenticationError.canceled }
        guard clock() < attempt.expiresAt else { pending = nil; throw ChatGPTAuthenticationError.authorizationExpired }
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.host == "127.0.0.1", components.port == attempt.callbackURL.port,
              components.path == "/auth/callback", components.user == nil, components.password == nil, components.fragment == nil else { throw ChatGPTAuthenticationError.invalidCallback }
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw ChatGPTAuthenticationError.invalidCallback }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let returnedState = fields["state"], secureEqual(returnedState, attempt.state) else { throw ChatGPTAuthenticationError.stateMismatch }
        if let error = fields["error"] {
            pending = nil
            if error == "access_denied" { throw ChatGPTAuthenticationError.authorizationDenied }
            throw ChatGPTAuthenticationError.oauth(code: safeCode(error), status: 0, requestID: nil)
        }
        guard let clientID = fields["client_id"] ?? attempt.clientID, validClientID(clientID),
              attempt.clientID == nil || attempt.clientID == clientID else { pending = nil; throw ChatGPTAuthenticationError.registrationIncomplete }
        guard let code = fields["code"], !code.isEmpty, code.count < 16_000 else { throw ChatGPTAuthenticationError.invalidCallback }
        let expectedGeneration = generation
        pending = nil; completingAttempt = attempt.id
        defer { if completingAttempt == attempt.id { completingAttempt = nil } }
        if attempt.clientID == nil {
            guard var checkpoint = state else { throw ChatGPTAuthenticationError.persistenceFailed }
            checkpoint.pendingClientID = clientID
            state = checkpoint
            try await persist(checkpoint)
            guard generation == expectedGeneration else { throw ChatGPTAuthenticationError.canceled }
        }
        let tokens = try await tokenRequest(["grant_type": "authorization_code", "client_id": clientID, "code": code,
                                             "code_verifier": attempt.verifier, "redirect_uri": attempt.callbackURL.absoluteString,
                                             "resource": "https://api.openai.com/v1"])
        let identity = try await validateIdentity(tokens.idToken, clientID: clientID, nonce: attempt.nonce)
        try Task.checkCancellation()
        guard generation == expectedGeneration, var next = state else { throw ChatGPTAuthenticationError.canceled }
        if let old = next.registrations.first(where: { $0.clientID == clientID }), old.subject != identity.subject { throw ChatGPTAuthenticationError.identityMismatch }
        let registration = ChatGPTRegistration(clientID: clientID, subject: identity.subject, issuer: identity.issuer,
                                              email: identity.email, displayName: identity.displayName, tokens: tokens)
        next.registrations.removeAll { $0.clientID == clientID }; next.registrations.append(registration); next.activeClientID = clientID
        if next.pendingClientID == clientID { next.pendingClientID = nil }
        try await persist(next)
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw ChatGPTAuthenticationError.canceled }
        state = next
        return registration.account
    }

    public func accessToken() async throws -> String {
        try await restore()
        guard let registration = selectedRegistration(), let tokens = registration.tokens else { throw ChatGPTAuthenticationError.notSignedIn }
        guard tokens.scopes.contains("chatgpt.tokens.use.direct") else { throw ChatGPTAuthenticationError.planUsageDisabled }
        if registration.pendingRefresh == nil, tokens.expiresAt.timeIntervalSince(clock()) > 60 { return tokens.accessToken }
        if registration.pendingRefresh == nil, let earliest = tokens.earliestRefreshAt, earliest > clock(), tokens.expiresAt > clock() { return tokens.accessToken }
        if let refresh { return try await refresh.value }
        let id = UUID(); let expectedGeneration = generation
        let task = Task { try await self.refreshToken(registration, generation: expectedGeneration) }
        refresh = task; refreshID = id
        defer { if refreshID == id { refresh = nil; refreshID = nil } }
        return try await task.value
    }

    /// Clears local credentials even if remote revocation cannot be confirmed.
    @discardableResult public func signOut() async throws -> Bool {
        try await restore()
        guard var next = state else { return true }
        let registration = selectedRegistration()
        generation = UUID(); pending = nil; completingAttempt = nil; refresh?.cancel(); refresh = nil; refreshID = nil
        next.registrations = next.registrations.map { value in
            var value = value
            if value.clientID == registration?.clientID { value.tokens = nil; value.pendingRefresh = nil }
            return value
        }
        state = next
        try await persist(next)
        guard let registration, let token = registration.pendingRefresh?.tokens.refreshToken ?? registration.tokens?.refreshToken, !token.isEmpty else { return true }
        do {
            let metadata = try await loadDiscovery()
            guard let endpoint = metadata.revocationEndpoint else { return false }
            let response = try await formRequest(url: endpoint, fields: ["token": token, "token_type_hint": "refresh_token", "client_id": registration.clientID])
            return response.statusCode == 200
        } catch { return false }
    }

    private func refreshToken(_ registration: ChatGPTRegistration, generation expectedGeneration: UUID, mayRenewExpiredRotation: Bool = true) async throws -> String {
        guard let old = registration.tokens else { throw ChatGPTAuthenticationError.notSignedIn }
        do {
            let rotation: ChatGPTPendingRefresh
            if let pending = registration.pendingRefresh { rotation = pending }
            else {
                let tokens = try await tokenRequest(["grant_type": "refresh_token", "client_id": registration.clientID,
                                                    "refresh_token": old.refreshToken, "resource": "https://api.openai.com/v1"], previous: old)
                rotation = ChatGPTPendingRefresh(tokens: tokens, receivedAt: clock())
            }
            try Task.checkCancellation()
            guard generation == expectedGeneration, var checkpoint = state,
                  let index = checkpoint.registrations.firstIndex(where: { $0.clientID == registration.clientID }) else { throw ChatGPTAuthenticationError.canceled }
            checkpoint.registrations[index].pendingRefresh = rotation
            // A consumed rotation must survive key retrieval failure without authorizing inference.
            state = checkpoint
            try await persist(checkpoint)
            if rotation.tokens.idToken != old.idToken {
                let identity = try await validateIdentity(rotation.tokens.idToken, clientID: registration.clientID, nonce: nil, receivedAt: rotation.receivedAt)
                guard identity.subject == registration.subject else { throw ChatGPTAuthenticationError.identityMismatch }
            }
            try Task.checkCancellation()
            guard generation == expectedGeneration, var next = state,
                  let currentIndex = next.registrations.firstIndex(where: { $0.clientID == registration.clientID }) else { throw ChatGPTAuthenticationError.canceled }
            next.registrations[currentIndex].tokens = rotation.tokens; next.registrations[currentIndex].pendingRefresh = nil
            try await persist(next)
            guard generation == expectedGeneration else { throw ChatGPTAuthenticationError.canceled }
            state = next
            guard rotation.tokens.scopes.contains("chatgpt.tokens.use.direct") else { throw ChatGPTAuthenticationError.planUsageDisabled }
            if rotation.tokens.expiresAt <= clock() {
                guard mayRenewExpiredRotation else { throw ChatGPTAuthenticationError.invalidTokenResponse }
                return try await refreshToken(next.registrations[currentIndex], generation: expectedGeneration, mayRenewExpiredRotation: false)
            }
            return rotation.tokens.accessToken
        } catch let error as ChatGPTAuthenticationError where error.requiresReauthorization {
            if generation == expectedGeneration, var next = state,
               let index = next.registrations.firstIndex(where: { $0.clientID == registration.clientID }) {
                next.registrations[index].tokens = nil; next.registrations[index].pendingRefresh = nil
                state = next
                try await persist(next)
            }
            throw error
        }
    }

    private func selectedRegistration() -> ChatGPTRegistration? {
        guard let state, let id = state.activeClientID else { return nil }
        return state.registrations.first { $0.clientID == id }
    }

    private func persist(_ value: ChatGPTCredentialState) async throws {
        let predecessor = writeTail; let vault = self.vault; let id = UUID()
        let task = Task {
            // Later clears must wait for every earlier write, including a failed write.
            if let predecessor { _ = try? await predecessor.value }
            try await vault.save(value)
        }
        writeTail = task; writeID = id
        defer { if writeID == id { writeTail = nil; writeID = nil } }
        do { try await task.value } catch { throw ChatGPTAuthenticationError.persistenceFailed }
    }

    private func tokenRequest(_ fields: [String: String], previous: ChatGPTTokenSet? = nil) async throws -> ChatGPTTokenSet {
        let response = try await formRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, fields: fields)
        guard response.statusCode == 200 else {
            let error = try? JSONDecoder().decode(OAuthFailure.self, from: response.data)
            let requestID = response.headers["openai-request-id"] ?? response.headers["x-request-id"]
            if let code = error?.error { throw ChatGPTAuthenticationError.oauth(code: safeCode(code), status: response.statusCode, requestID: requestID) }
            throw ChatGPTAuthenticationError.http(status: response.statusCode, requestID: requestID)
        }
        guard response.data.count < 128_000, let body = try? JSONDecoder().decode(TokenResponse.self, from: response.data),
              let idToken = body.idToken ?? previous?.idToken, !idToken.isEmpty,
              let scope = body.scope ?? previous?.scopes.sorted().joined(separator: " ") else { throw ChatGPTAuthenticationError.invalidTokenResponse }
        let scopes = Set(scope.split(whereSeparator: \.isWhitespace).map(String.init))
        if previous != nil || scopes.contains("chatgpt.tokens.use.direct") || scopes.contains("offline_access") {
            guard let access = body.accessToken, validToken(access), let refresh = body.refreshToken, validToken(refresh),
                  body.tokenType?.lowercased() == "bearer", let expiry = body.expiresIn, expiry > 0, expiry <= 86_400 else { throw ChatGPTAuthenticationError.invalidTokenResponse }
        }
        return ChatGPTTokenSet(accessToken: body.accessToken ?? "", refreshToken: body.refreshToken ?? "", idToken: idToken, scopes: scopes,
                               expiresAt: clock().addingTimeInterval(body.expiresIn ?? 0), earliestRefreshAt: body.earliestRefreshAt.map(Date.init(timeIntervalSince1970:)))
    }

    private func formRequest(url: URL, fields: [String: String]) async throws -> ServiceHTTPResponse {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))! }
        request.httpBody = Data(fields.sorted(by: { $0.key < $1.key }).map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&").utf8)
        return try await transport.send(request)
    }

    private func loadDiscovery() async throws -> Discovery {
        if let discovery { return discovery }
        let response = try await transport.send(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
        guard response.statusCode == 200, response.data.count < 64_000,
              let metadata = try? JSONDecoder().decode(Discovery.self, from: response.data), metadata.issuer == "https://auth.openai.com",
              trustedAuthURL(metadata.jwksURI), metadata.revocationEndpoint.map(trustedAuthURL) ?? true else { throw ChatGPTAuthenticationError.invalidIDToken }
        discovery = metadata
        return metadata
    }

    private func validateIdentity(_ token: String, clientID: String, nonce: String?, receivedAt: Date? = nil) async throws -> ChatGPTIDTokenValidator.Identity {
        let metadata = try await loadDiscovery()
        let cached = jwks != nil && clock().timeIntervalSince(keysFetchedAt ?? .distantPast) < 300
        if !cached { try await fetchKeys(metadata.jwksURI) }
        do { return try validator.validate(token, jwks: jwks!, clientID: clientID, nonce: nonce, now: receivedAt ?? clock()) }
        catch {
            guard cached else { throw error }
            try await fetchKeys(metadata.jwksURI)
            return try validator.validate(token, jwks: jwks!, clientID: clientID, nonce: nonce, now: receivedAt ?? clock())
        }
    }

    private func fetchKeys(_ url: URL) async throws {
        let response = try await transport.send(URLRequest(url: url))
        guard response.statusCode == 200, response.data.count < 256_000 else { throw ChatGPTAuthenticationError.invalidIDToken }
        jwks = response.data; keysFetchedAt = clock()
    }
    private func validClientID(_ id: String) -> Bool { id != "dynamic_agent_client" && !id.isEmpty && id.count <= 200 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
    private func validToken(_ value: String) -> Bool { !value.isEmpty && value.utf8.count < 64_000 && value.utf8.allSatisfy { $0 > 32 && $0 < 127 } }
    private func trustedAuthURL(_ url: URL) -> Bool { url.scheme == "https" && url.host == "auth.openai.com" && url.port == nil && url.user == nil && url.password == nil && url.fragment == nil }
    private func safeCode(_ value: String) -> String { value.count < 128 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } ? value : "oauth_error" }
    private func secureEqual(_ one: String, _ two: String) -> Bool {
        let left = Array(one.utf8); let right = Array(two.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
    private struct Discovery: Decodable, Sendable {
        let issuer: String; let jwksURI: URL; let revocationEndpoint: URL?
        enum CodingKeys: String, CodingKey { case issuer, jwksURI = "jwks_uri", revocationEndpoint = "revocation_endpoint" }
    }
    private struct OAuthFailure: Decodable { let error: String }
    private struct TokenResponse: Decodable {
        let accessToken: String?; let refreshToken: String?; let idToken: String?; let tokenType: String?
        let expiresIn: Double?; let scope: String?; let earliestRefreshAt: Double?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token", tokenType = "token_type", expiresIn = "expires_in", scope, earliestRefreshAt = "earliest_refresh_at" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken); refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
            idToken = try c.decodeIfPresent(String.self, forKey: .idToken); tokenType = try c.decodeIfPresent(String.self, forKey: .tokenType)
            expiresIn = try c.decodeIfPresent(Double.self, forKey: .expiresIn); scope = try c.decodeIfPresent(String.self, forKey: .scope)
            if let number = try? c.decode(Double.self, forKey: .earliestRefreshAt) { earliestRefreshAt = number }
            else if let text = try? c.decode(String.self, forKey: .earliestRefreshAt) {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                earliestRefreshAt = Double(text) ?? formatter.date(from: text)?.timeIntervalSince1970 ?? ISO8601DateFormatter().date(from: text)?.timeIntervalSince1970
            } else { earliestRefreshAt = nil }
        }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import EngineeringCore
@testable import EngineeringServices

private actor AuthVault: ChatGPTCredentialVault {
    private(set) var value: ChatGPTCredentialState?
    var failNextSave = false
    private(set) var saves = 0
    private var shouldHoldSave = false
    private var heldSave: CheckedContinuation<Void, Never>?
    private var saveObserver: CheckedContinuation<Void, Never>?
    func load() -> ChatGPTCredentialState? { value }
    func save(_ state: ChatGPTCredentialState) async throws {
        if failNextSave { failNextSave = false; throw ChatGPTAuthenticationError.persistenceFailed }
        if shouldHoldSave {
            shouldHoldSave = false
            await withCheckedContinuation { continuation in
                heldSave = continuation
                let observer = saveObserver; saveObserver = nil; observer?.resume()
            }
        }
        saves += 1; value = state
    }
    func holdNextSave() { shouldHoldSave = true }
    func waitForHeldSave() async {
        if heldSave != nil { return }
        await withCheckedContinuation { saveObserver = $0 }
    }
    func releaseSave() { let continuation = heldSave; heldSave = nil; continuation?.resume() }
    func rejectNextSave() { failNextSave = true }
}

private actor AuthTransport: ServiceHTTPTransport {
    private var responses: [ServiceHTTPResponse]
    private(set) var requests: [URLRequest] = []
    private var gateRefresh = false
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    init(_ responses: [ServiceHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        requests.append(request)
        for (count, continuation) in observers where requests.count >= count { continuation.resume() }
        observers.removeAll { requests.count >= $0.0 }
        guard !responses.isEmpty else { throw ChatGPTAuthenticationError.invalidTokenResponse }
        let result = responses.removeFirst()
        if gateRefresh, String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("grant_type=refresh_token") == true {
            await withCheckedContinuation { gate = $0 }
        }
        return result
    }
    func append(_ values: [ServiceHTTPResponse]) { responses.append(contentsOf: values) }
    func holdRefresh() { gateRefresh = true }
    func releaseRefresh() { gateRefresh = false; let gate = gate; self.gate = nil; gate?.resume() }
    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
}

private struct AuthCrypto: ChatGPTAuthorizationCryptography {
    func randomToken() -> String { UUID().uuidString + UUID().uuidString }
    func challenge(for verifier: String) -> String { "test-injected-S256" }
}
private struct AuthVerifier: ChatGPTJWTSignatureVerifying {
    var accepted = true
    func verify(message: Data, signature: Data, modulus: Data, exponent: Data) -> Bool { accepted }
}
private let authNow = Date(timeIntervalSince1970: 1_800_000_000)
private func authResponse(_ object: [String: Any], status: Int = 200) throws -> ServiceHTTPResponse {
    ServiceHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), statusCode: status)
}
private func encodeJWT(_ object: [String: Any]) throws -> String {
    try JSONSerialization.data(withJSONObject: object).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
private func jwt(nonce: String? = nil, client: String = "oaiapp_first", subject: String = "subject-first", issuer: String = "https://auth.openai.com", expiry: Double = 1_800_003_600) throws -> String {
    var claims: [String: Any] = ["iss": issuer, "sub": subject, "aud": client, "iat": authNow.timeIntervalSince1970, "exp": expiry, "email": "shared@example.com", "name": "Personal account"]
    if let nonce { claims["nonce"] = nonce }
    return try encodeJWT(["alg": "RS256", "kid": "key-1"]) + "." + encodeJWT(claims) + ".c2lnbmF0dXJl"
}
private func tokenResponse(_ jwt: String, scopes: String = "openid offline_access chatgpt.tokens.use.direct", expiry: Double = 3_600, access: String = "test-access", refresh: String = "test-refresh") throws -> ServiceHTTPResponse {
    try authResponse(["access_token": access, "refresh_token": refresh, "id_token": jwt, "token_type": "Bearer", "expires_in": expiry, "scope": scopes])
}
private func discoveryResponse() throws -> ServiceHTTPResponse {
    try authResponse(["issuer": "https://auth.openai.com", "jwks_uri": "https://auth.openai.com/.well-known/jwks.json", "revocation_endpoint": "https://auth.openai.com/oauth/revoke"])
}
private func keysResponse() throws -> ServiceHTTPResponse {
    let modulus = Data(repeating: 0x9a, count: 256).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return try authResponse(["keys": [["kty": "RSA", "kid": "key-1", "alg": "RS256", "use": "sig", "n": modulus, "e": "AQAB"]]])
}
private func fields(_ attempt: ChatGPTAuthorizationAttempt) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}
private func callback(_ attempt: ChatGPTAuthorizationAttempt, client: String = "oaiapp_first", state: String? = nil) -> URL {
    var url = URLComponents(url: attempt.callbackURL, resolvingAgainstBaseURL: false)!
    url.queryItems = [URLQueryItem(name: "code", value: "one-time-code"), URLQueryItem(name: "state", value: state ?? fields(attempt)["state"]!), URLQueryItem(name: "client_id", value: client)]
    return url.url!
}
private func session(vault: AuthVault, transport: AuthTransport, signatureAccepted: Bool = true) -> ChatGPTSession {
    ChatGPTSession(vault: vault, transport: transport, signatureVerifier: AuthVerifier(accepted: signatureAccepted), authorizationCryptography: AuthCrypto(), clock: { authNow })
}
private func signedIn(expiry: Double = 3_600, extra: [ServiceHTTPResponse] = []) async throws -> (ChatGPTSession, AuthVault, AuthTransport) {
    let vault = AuthVault(); let transport = AuthTransport([])
    let connected = session(vault: vault, transport: transport)
    let attempt = try await connected.beginAuthorization(port: 4_321)
    await transport.append(try [tokenResponse(jwt(nonce: fields(attempt)["nonce"]!), expiry: expiry), discoveryResponse(), keysResponse()] + extra)
    _ = try await connected.completeAuthorization(callbackURL: callback(attempt))
    return (connected, vault, transport)
}

@Test func authPersistsStableHostBeforeBrowserAndUsesFreshTransactionValues() async throws {
    let vault = AuthVault(); let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    let first = try await connection.beginAuthorization(port: 4_321)
    let one = fields(first)
    #expect(await vault.saves == 1)
    #expect(one["client_id"] == "dynamic_agent_client")
    #expect(one["agent_name_hint"] == "Engineering Studio")
    #expect(one["redirect_uri"] == "http://127.0.0.1:4321/auth/callback")
    #expect(one["scope"]?.contains("chatgpt.tokens.use.direct") == true)
    #expect(one["resource"] == "https://api.openai.com/v1")
    #expect(one["code_challenge_method"] == "S256")
    await connection.cancelAuthorization()
    let second = try await connection.beginAuthorization(port: 5_432)
    let two = fields(second)
    #expect(one["ext_agent_host_id"] == two["ext_agent_host_id"])
    #expect(one["state"] != two["state"] && one["nonce"] != two["nonce"])
    #expect(await transport.requests.isEmpty)
}

@Test func authWrongStateAndUntrustedLoopbackNeverExchangeCode() async throws {
    let vault = AuthVault(); let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await #expect(throws: ChatGPTAuthenticationError.stateMismatch) { try await connection.completeAuthorization(callbackURL: callback(attempt, state: "wrong")) }
    let wrongHost = URL(string: callback(attempt).absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))!
    await #expect(throws: ChatGPTAuthenticationError.invalidCallback) { try await connection.completeAuthorization(callbackURL: wrongHost) }
    #expect(await transport.requests.isEmpty)
}

@Test func authNewRegistrationMissingIssuedIDAndDeniedConsentAreNotTokens() async throws {
    let vault = AuthVault(); let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    var missing = URLComponents(url: callback(attempt), resolvingAgainstBaseURL: false)!
    missing.queryItems?.removeAll { $0.name == "client_id" }
    await #expect(throws: ChatGPTAuthenticationError.registrationIncomplete) { try await connection.completeAuthorization(callbackURL: missing.url!) }
    let denied = try await connection.beginAuthorization(port: 4_321)
    var url = URLComponents(url: denied.callbackURL, resolvingAgainstBaseURL: false)!
    url.queryItems = [URLQueryItem(name: "state", value: fields(denied)["state"]), URLQueryItem(name: "error", value: "access_denied")]
    await #expect(throws: ChatGPTAuthenticationError.authorizationDenied) { try await connection.completeAuthorization(callbackURL: url.url!) }
    #expect(await transport.requests.isEmpty)
}

@Test func authStoresOnlyValidatedRegistrationAndExchangeHasExactPublicClientFields() async throws {
    let (connection, vault, transport) = try await signedIn()
    #expect(try await connection.accessToken() == "test-access")
    #expect(await connection.activeAccount()?.planUsageEnabled == true)
    #expect(await vault.value?.registrations.count == 1)
    let request = try #require(await transport.requests.first)
    #expect(request.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/token")
    let body = String(data: request.httpBody!, encoding: .utf8)!
    #expect(body.contains("client_id=oaiapp_first"))
    #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fauth%2Fcallback"))
    #expect(body.contains("code_verifier="))
    #expect(!body.contains("client_secret") && request.value(forHTTPHeaderField: "Authorization") == nil)
    let attempt = try await connection.beginAuthorization(port: 8_888, accountID: "oaiapp_first")
    #expect(fields(attempt)["client_id"] == "oaiapp_first")
    #expect(fields(attempt)["agent_name_hint"] == nil)
    #expect(fields(attempt)["id_token_hint"] != nil)
}

@Test func authRefreshCoalescesAndAtomicallyRotatesCredentialPair() async throws {
    let refreshed = try tokenResponse(jwt(), access: "next-access", refresh: "next-refresh")
    let (connection, vault, transport) = try await signedIn(expiry: 15, extra: [refreshed])
    await transport.holdRefresh()
    async let one = connection.accessToken()
    await transport.waitForRequests(4)
    async let two = connection.accessToken()
    await transport.releaseRefresh()
    #expect(try await one == "next-access")
    #expect(try await two == "next-access")
    #expect(await transport.requests.count == 4)
    let saved = try #require(await vault.value?.registrations.first?.tokens)
    #expect(saved.accessToken == "next-access" && saved.refreshToken == "next-refresh")
    let request = try #require(await transport.requests.last)
    let body = String(data: request.httpBody!, encoding: .utf8)!
    #expect(body.contains("grant_type=refresh_token"))
    #expect(!body.contains("scope="))
}

@Test func authTerminalRefreshClearsTokensButRetainsClientAndHost() async throws {
    let (connection, vault, _) = try await signedIn(expiry: 15, extra: [authResponse(["error": "invalid_grant"], status: 400)])
    let host = await vault.value?.hostID
    await #expect(throws: ChatGPTAuthenticationError.oauth(code: "invalid_grant", status: 400, requestID: nil)) { try await connection.accessToken() }
    #expect(await vault.value?.hostID == host)
    #expect(await vault.value?.registrations.first?.clientID == "oaiapp_first")
    #expect(await vault.value?.registrations.first?.tokens == nil)
}

@Test func authTransientRefreshFailurePreservesCredentials() async throws {
    let (connection, vault, _) = try await signedIn(expiry: 15, extra: [authResponse(["detail": "temporary"], status: 503)])
    await #expect(throws: ChatGPTAuthenticationError.http(status: 503, requestID: nil)) { try await connection.accessToken() }
    #expect(await vault.value?.registrations.first?.tokens?.refreshToken == "test-refresh")
}

@Test func authSignoutFencesLateRefreshAndRetainsStableRegistration() async throws {
    let refresh = try tokenResponse(jwt(), access: "late-access", refresh: "late-refresh")
    let (connection, vault, transport) = try await signedIn(expiry: 15, extra: [refresh, ServiceHTTPResponse(data: Data(), statusCode: 200)])
    await transport.holdRefresh()
    let task = Task { try await connection.accessToken() }
    await transport.waitForRequests(4)
    #expect(try await connection.signOut())
    await transport.releaseRefresh()
    do { _ = try await task.value; Issue.record("Late refresh must not return an access token") } catch { }
    #expect(await vault.value?.registrations.first?.tokens == nil)
    #expect(await connection.activeAccount()?.isSignedIn == false)
    #expect(await connection.accounts().count == 1)
}

@Test func authSignoutReportsUnconfirmedRevocationAndStillClearsLocalTokens() async throws {
    let (connection, vault, _) = try await signedIn(extra: [ServiceHTTPResponse(data: Data(), statusCode: 503)])
    #expect(try await !connection.signOut())
    #expect(await vault.value?.registrations.first?.tokens == nil)
    let attempt = try await connection.beginAuthorization(port: 4_321, accountID: "oaiapp_first")
    #expect(fields(attempt)["id_token_hint"] == nil)
    #expect(fields(attempt)["client_id"] == "oaiapp_first")
}

@Test func authFailedSecureHostWritePreventsAuthorization() async throws {
    let vault = AuthVault(); await vault.rejectNextSave()
    let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    await #expect(throws: ChatGPTAuthenticationError.persistenceFailed) { try await connection.beginAuthorization(port: 4_321) }
    #expect(await transport.requests.isEmpty)
}

@Test func authIDTokenRejectsBadSignatureIssuerAudienceNonceAndExpiry() throws {
    let keys = try keysResponse().data
    let validator = ChatGPTIDTokenValidator(verifier: AuthVerifier())
    for token in try [jwt(nonce: "different"), jwt(nonce: "expected", client: "oaiapp_other"), jwt(nonce: "expected", issuer: "https://attacker.invalid"), jwt(nonce: "expected", expiry: authNow.timeIntervalSince1970 - 30)] {
        #expect(throws: ChatGPTAuthenticationError.invalidIDToken) { try validator.validate(token, jwks: keys, clientID: "oaiapp_first", nonce: "expected", now: authNow) }
    }
    let bad = ChatGPTIDTokenValidator(verifier: AuthVerifier(accepted: false))
    #expect(throws: ChatGPTAuthenticationError.invalidIDToken) { try bad.validate(jwt(nonce: "expected"), jwks: keys, clientID: "oaiapp_first", nonce: "expected", now: authNow) }
}

@Test func authLoopbackHTTPParserRejectsHostConfusionAndDuplicateState() throws {
    let valid = Data("GET /auth/callback?code=code&state=pending HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8)
    #expect(try ChatGPTLoopbackRequest.callbackURL(header: valid, port: 4_321, expectedState: "pending").host == "127.0.0.1")
    for text in ["GET /auth/callback?state=pending HTTP/1.1\r\nHost: localhost:4321\r\n\r\n", "GET /auth/callback?state=pending&state=pending HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n", "POST /auth/callback?state=pending HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n"] {
        #expect(throws: (any Error).self) { try ChatGPTLoopbackRequest.callbackURL(header: Data(text.utf8), port: 4_321, expectedState: "pending") }
    }
}

@Test func authIdentityOnlyConsentIsSavedWithoutEnablingInference() async throws {
    let vault = AuthVault(); let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await transport.append(try [authResponse(["id_token": jwt(nonce: fields(attempt)["nonce"]!), "scope": "openid profile email"]), discoveryResponse(), keysResponse()])
    let account = try await connection.completeAuthorization(callbackURL: callback(attempt))
    #expect(account.isSignedIn && !account.planUsageEnabled)
    await #expect(throws: ChatGPTAuthenticationError.planUsageDisabled) { try await connection.accessToken() }
    #expect(await vault.value?.registrations.first?.tokens?.idToken != nil)
}

@Test func authRotatedTokenCheckpointSurvivesVaultFailureWithoutSecondGrant() async throws {
    let refreshed = try tokenResponse(jwt(), access: "rotated-access", refresh: "rotated-refresh")
    let (connection, vault, transport) = try await signedIn(expiry: 15, extra: [refreshed])
    await vault.rejectNextSave()
    await #expect(throws: ChatGPTAuthenticationError.persistenceFailed) { try await connection.accessToken() }
    // In-memory checkpoint retains the consumed grant; retry saves and verifies it, never refreshes twice.
    #expect(try await connection.accessToken() == "rotated-access")
    #expect(await transport.requests.count == 4)
    #expect(await vault.value?.registrations.first?.tokens?.refreshToken == "rotated-refresh")
    #expect(await vault.value?.registrations.first?.pendingRefresh == nil)
}

@Test func authRefreshCanOmitUnchangedScopeAndIdentityToken() async throws {
    let response = try authResponse(["access_token": "rotated-access", "refresh_token": "rotated-refresh", "token_type": "Bearer", "expires_in": 3_600, "earliest_refresh_at": "2027-01-15T08:00:00Z"])
    let (connection, vault, transport) = try await signedIn(expiry: 15, extra: [response])
    #expect(try await connection.accessToken() == "rotated-access")
    #expect(await vault.value?.registrations.first?.tokens?.scopes.contains("chatgpt.tokens.use.direct") == true)
    #expect(await vault.value?.registrations.first?.tokens?.earliestRefreshAt != nil)
    #expect(await transport.requests.count == 4)
}

@Test func authAccountRegistrationsRemainSeparateEvenWhenEmailMatches() async throws {
    let (connection, vault, transport) = try await signedIn()
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await transport.append(try [tokenResponse(jwt(nonce: fields(attempt)["nonce"]!, client: "oaiapp_second", subject: "subject-second"))])
    let second = try await connection.completeAuthorization(callbackURL: callback(attempt, client: "oaiapp_second"))
    #expect(second.id == "oaiapp_second")
    #expect(await connection.accounts().count == 2)
    #expect(await vault.value?.registrations.count == 2)
    try await connection.selectAccount(id: "oaiapp_first")
    #expect(await connection.activeAccount()?.id == "oaiapp_first")
}

@Test func authReturningCallbackCannotSwapItsSelectedClient() async throws {
    let (connection, _, transport) = try await signedIn()
    let attempt = try await connection.beginAuthorization(port: 4_321, accountID: "oaiapp_first")
    await #expect(throws: ChatGPTAuthenticationError.registrationIncomplete) { try await connection.completeAuthorization(callbackURL: callback(attempt, client: "oaiapp_other")) }
    #expect(await transport.requests.count == 3)
    #expect(await connection.activeAccount()?.id == "oaiapp_first")
}

@Test func authFailedCodeExchangeRetriesIssuedClientInsteadOfRegisteringAgain() async throws {
    let vault = AuthVault(); let transport = AuthTransport(try [authResponse(["error": "invalid_grant"], status: 400)])
    let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await #expect(throws: ChatGPTAuthenticationError.oauth(code: "invalid_grant", status: 400, requestID: nil)) { try await connection.completeAuthorization(callbackURL: callback(attempt)) }
    let retry = try await connection.beginAuthorization(port: 5_432)
    #expect(fields(retry)["client_id"] == "oaiapp_first")
    #expect(fields(retry)["agent_name_hint"] == nil)
}

@Test func authProtectedRotationResumesAfterRestartAndJWKSOutageWithoutRefreshingAgain() async throws {
    let token = try jwt().split(separator: ".")
    let rotatedJWT = try encodeJWT(["alg": "RS256", "kid": "key-2"]) + "." + token[1] + "." + token[2]
    let refreshed = try tokenResponse(rotatedJWT, access: "rotated-access", refresh: "rotated-refresh")
    let (connection, vault, transport) = try await signedIn(expiry: 15, extra: [refreshed, ServiceHTTPResponse(data: Data(), statusCode: 503)])
    await #expect(throws: ChatGPTAuthenticationError.invalidIDToken) { try await connection.accessToken() }
    #expect(await vault.value?.registrations.first?.tokens?.accessToken == "test-access")
    #expect(await vault.value?.registrations.first?.pendingRefresh?.tokens.refreshToken == "rotated-refresh")
    let replacementKeys = String(data: try keysResponse().data, encoding: .utf8)!.replacingOccurrences(of: "key-1", with: "key-2")
    let nextTransport = AuthTransport(try [discoveryResponse(), ServiceHTTPResponse(data: Data(replacementKeys.utf8), statusCode: 200)])
    let restored = session(vault: vault, transport: nextTransport)
    #expect(try await restored.accessToken() == "rotated-access")
    #expect(await nextTransport.requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(await transport.requests.count == 5)
    #expect(await vault.value?.registrations.first?.pendingRefresh == nil)
}

@Test func authRefreshedIdentityCannotReplaceSelectedSubject() async throws {
    let (connection, vault, _) = try await signedIn(expiry: 15, extra: [tokenResponse(jwt(subject: "different-subject"), access: "unverified-access", refresh: "unverified-refresh")])
    await #expect(throws: ChatGPTAuthenticationError.identityMismatch) { try await connection.accessToken() }
    #expect(await vault.value?.registrations.first?.subject == "subject-first")
    #expect(await vault.value?.registrations.first?.tokens?.accessToken == "test-access")
    #expect(await vault.value?.registrations.first?.pendingRefresh?.tokens.accessToken == "unverified-access")
}

@Test func authCanceledAttemptCannotExchangeOrActivateCredentials() async throws {
    let vault = AuthVault(); let transport = AuthTransport([]); let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await transport.append(try [tokenResponse(jwt(nonce: fields(attempt)["nonce"]!)), discoveryResponse(), keysResponse()])
    // Consume the transaction, then cancel before a caller can reuse it.
    await connection.cancelAuthorization()
    await #expect(throws: ChatGPTAuthenticationError.canceled) { try await connection.completeAuthorization(callbackURL: callback(attempt)) }
    #expect(await vault.value?.registrations.isEmpty == true)
    #expect(await transport.requests.isEmpty)
}

@Test func authSerializedVaultWritesPreventLateRefreshDiskResurrectionAfterSignout() async throws {
    let (connection, vault, _) = try await signedIn(expiry: 15, extra: [tokenResponse(jwt(), access: "late-access", refresh: "late-refresh"), ServiceHTTPResponse(data: Data(), statusCode: 200)])
    await vault.holdNextSave()
    let refreshing = Task { try await connection.accessToken() }
    await vault.waitForHeldSave()
    let release = Task {
        try await Task.sleep(for: .milliseconds(20))
        await vault.releaseSave()
    }
    #expect(try await connection.signOut())
    _ = try await release.value
    do { _ = try await refreshing.value; Issue.record("Sign-out must reject the late refresh") } catch { }
    #expect(await vault.value?.registrations.first?.tokens == nil)
    #expect(await vault.value?.registrations.first?.pendingRefresh == nil)
    let restored = session(vault: vault, transport: AuthTransport([]))
    try await restored.restore()
    #expect(await restored.activeAccount()?.isSignedIn == false)
    await #expect(throws: ChatGPTAuthenticationError.notSignedIn) { try await restored.accessToken() }
}

@Test func authFailedRegistrationExchangeRetainsIssuedClientAcrossRestart() async throws {
    let vault = AuthVault(); let transport = AuthTransport(try [authResponse(["error": "invalid_grant"], status: 400)])
    let first = session(vault: vault, transport: transport)
    let attempt = try await first.beginAuthorization(port: 4_321)
    await #expect(throws: ChatGPTAuthenticationError.oauth(code: "invalid_grant", status: 400, requestID: nil)) { try await first.completeAuthorization(callbackURL: callback(attempt)) }
    #expect(await vault.value?.pendingClientID == "oaiapp_first")
    let restarted = session(vault: vault, transport: AuthTransport([]))
    let retry = try await restarted.beginAuthorization(port: 5_432)
    #expect(fields(retry)["client_id"] == "oaiapp_first")
    #expect(await restarted.accounts().isEmpty)
}

@Test func authSignoutDuringFirstRegistrationCannotCommitLateTokens() async throws {
    let vault = AuthVault(); let transport = AuthTransport([])
    let connection = session(vault: vault, transport: transport)
    let attempt = try await connection.beginAuthorization(port: 4_321)
    await vault.holdNextSave()
    let signingIn = Task { try await connection.completeAuthorization(callbackURL: callback(attempt)) }
    await vault.waitForHeldSave()
    let release = Task {
        try await Task.sleep(for: .milliseconds(20))
        await vault.releaseSave()
    }
    #expect(try await connection.signOut())
    _ = try await release.value
    await #expect(throws: ChatGPTAuthenticationError.canceled) { try await signingIn.value }
    #expect(await transport.requests.isEmpty)
    #expect(await vault.value?.registrations.isEmpty == true)
    #expect(await vault.value?.pendingClientID == "oaiapp_first")
}

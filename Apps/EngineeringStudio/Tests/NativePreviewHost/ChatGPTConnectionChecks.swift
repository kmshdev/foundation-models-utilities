@testable import WorkspaceFeature
@testable import StudioWorkflows
@testable import StudioServices
import StudioUI
import EngineeringWorkflows
import EngineeringServices
import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the actual observable connection with a restored fixture registration.
/// No account browser, external HTTP, native credential storage or production token is used.
@MainActor
func checkChatGPTConnection() async throws {
    let clientID = "oaiapp_connectioncheck_\(UUID().uuidString)"
    defer { UserDefaults.standard.removeObject(forKey: "chatgpt.selectedModel.\(clientID)") }
    let vault = ChatGPTConnectionCheckVault(state: try connectionCheckState(clientID: clientID))
    let catalog = ChatGPTConnectionCheckTransport()
    let session = ChatGPTSession(vault: vault, transport: catalog, signatureVerifier: ChatGPTConnectionCheckVerifier(),
                                 authorizationCryptography: ChatGPTConnectionCheckCryptography())
    let client = ChatGPTResponsesClient(tokenProvider: session, catalogTransport: catalog)
    let connection = ChatGPTConnection(session: session, client: client)
    var replacementHooks = 0
    connection.configureBeforeAccountChange { replacementHooks += 1 }
    try connectionRequire(!connection.isReadyForPlanning && connection.catalogState == .notLoaded,
                          "Construction does not claim model access")
    await connection.load()
    try connectionRequire(connection.isSignedIn && connection.isReadyForPlanning && connection.status == "Connected",
                          "Only a verified catalog and selected account establish model readiness")
    try connectionRequire(connection.catalogState == .available && !connection.isRefreshing &&
                          (try connection.requireSelectedModel()) == "fixture-model",
                          "A completed subscription catalog permits planning")
    try connectionRequire(replacementHooks == 0, "Initial model selection does not stop an unrelated runtime")

    await catalog.setStatus(401)
    await connection.refreshModels()
    try connectionRequire(!connection.isReadyForPlanning && connection.catalogState == .failed &&
                          connection.status == "Model access unavailable" && connection.error != nil,
                          "HTTP 401 rejects cached readiness and Connected status")
    try connectionRequire(connection.models.map(\.slug) == ["fixture-model"],
                          "Prior choices remain inspectable without establishing current account access")
    do {
        _ = try connection.requireSelectedModel()
        throw connectionFailure("Failed catalog must block planning")
    } catch ChatGPTConnectionError.modelAccessUnavailable { }

    await catalog.setStatus(200)
    await connection.refreshModels()
    try connectionRequire(connection.isReadyForPlanning && connection.error == nil,
                          "A later verified refresh restores readiness")

    await catalog.suspendNextRequest()
    let refreshing = Task { @MainActor in await connection.refreshModels() }
    try await waitForConnectionCatalogGate(catalog)
    try connectionRequire(connection.isRefreshing && connection.catalogState == .loading,
                          "A delayed request exposes loading ownership")
    await connection.signIn(addAccount: true)
    try connectionRequire(!connection.isSigningIn && connection.isRefreshing,
                          "Sign-in during catalog refresh returns without changing refresh ownership")
    await catalog.releaseRequest()
    await refreshing.value
    try connectionRequire(!connection.isRefreshing && !connection.isSigningIn && connection.isReadyForPlanning,
                          "The original delayed refresh completes without stuck flags")
    try connectionRequire(await catalog.authorizationRequests == 0,
                          "The protected overlap never begins account authentication")

    connection.configureBeforeAccountChange {
        replacementHooks += 1
        await catalog.waitForReplacementRelease()
    }
    await catalog.setModelSlugs(["fixture-replacement"])
    let replacing = Task { @MainActor in await connection.refreshModels() }
    try await waitForConnectionReplacementGate(catalog)
    try connectionRequire(connection.isRefreshing && connection.isChangingAccountOrModel &&
                          !connection.isReadyForPlanning && connection.selectedModel == "fixture-model" &&
                          connection.models.map(\.slug) == ["fixture-model"] && replacementHooks == 1,
                          "Catalog replacement awaits executor shutdown before exposing the new model")
    await catalog.releaseReplacement()
    await replacing.value
    try connectionRequire(connection.isReadyForPlanning && connection.selectedModel == "fixture-replacement" &&
                          !connection.isRefreshing && !connection.isChangingAccountOrModel,
                          "Acknowledged model replacement restores readiness and releases only its own gate")

    await catalog.setModelSlugs([])
    let removing = Task { @MainActor in await connection.refreshModels() }
    try await waitForConnectionReplacementGate(catalog)
    try connectionRequire(!connection.isReadyForPlanning && connection.selectedModel == "fixture-replacement" &&
                          replacementHooks == 2, "Model disappearance also waits for executor shutdown")
    await catalog.releaseReplacement()
    await removing.value
    try connectionRequire(connection.selectedModel == nil && connection.models.isEmpty && connection.error != nil &&
                          !connection.isReadyForPlanning && !connection.isRefreshing && !connection.isChangingAccountOrModel,
                          "An empty replacement catalog never claims Connected or leaves transition flags stuck")

    await catalog.setModelSlugs(["fixture-model"])
    await connection.refreshModels()
    try connectionRequire(connection.isReadyForPlanning && replacementHooks == 2,
                          "Recovering from no selected model does not stop the runtime unnecessarily")
    await catalog.setModelSlugs(["obsolete-replacement"])
    let obsoleteReplacement = Task { @MainActor in await connection.refreshModels() }
    try await waitForConnectionReplacementGate(catalog)
    connection.cancelSignIn() // Invalidate the generation while its lifecycle hook is suspended.
    await catalog.releaseReplacement()
    await obsoleteReplacement.value
    try connectionRequire(connection.selectedModel == "fixture-model" && connection.models.map(\.slug) == ["fixture-model"] &&
                          !connection.isReadyForPlanning && !connection.isRefreshing && !connection.isChangingAccountOrModel,
                          "An obsolete replacement cannot publish after the connection generation changes")
    connection.configureBeforeAccountChange { replacementHooks += 1 }
    await catalog.setModelSlugs(["fixture-model"])
    await connection.refreshModels()
    try connectionRequire(connection.isReadyForPlanning && replacementHooks == 3,
                          "A new verified catalog recovers from the cancelled replacement without replaying its hook")

    await vault.setFailSaves(true)
    await connection.signOut()
    try connectionRequire(!connection.isSignedIn && !connection.isReadyForPlanning &&
                          connection.activeAccount?.isSignedIn == false && connection.models.isEmpty &&
                          connection.selectedModel == nil && connection.catalogState == .notLoaded && connection.error != nil,
                          "Failed protected sign-out save still exposes cleared in-memory credentials and no readiness")
    try connectionRequire(await session.activeAccount()?.isSignedIn == false,
                          "Connection mirrors the real session's fail-closed sign-out state")
    do {
        _ = try connection.requireSelectedModel()
        throw connectionFailure("A signed-out session must reject planning")
    } catch ChatGPTConnectionError.notConnected { }
    print("ChatGPT connection checks passed: verified readiness, rejected stale catalog, fenced catalog replacements, refresh/sign-in ownership, and fail-closed sign-out.")
}

private func connectionCheckState(clientID: String) throws -> ChatGPTCredentialState {
    let registration: [String: Any] = [
        "clientID": clientID, "subject": "isolated-fixture-subject", "issuer": "https://auth.openai.com",
        "email": "fixture@example.invalid", "displayName": "Isolated fixture",
        "tokens": ["accessToken": "fixture-oauth-only", "refreshToken": "fixture-refresh-only",
                   "idToken": "fixture-restored-identity", "scopes": ["openid", "offline_access", "chatgpt.tokens.use.direct"],
                   "expiresAt": Date().addingTimeInterval(3_600).timeIntervalSinceReferenceDate]
    ]
    let data = try JSONSerialization.data(withJSONObject: registration)
    let saved = try JSONDecoder().decode(ChatGPTRegistration.self, from: data)
    return .init(hostID: "urn:uuid:\(UUID().uuidString.lowercased())", registrations: [saved], activeClientID: clientID)
}

private actor ChatGPTConnectionCheckVault: ChatGPTCredentialVault {
    private var state: ChatGPTCredentialState
    private var failSaves = false
    init(state: ChatGPTCredentialState) { self.state = state }
    func load() -> ChatGPTCredentialState? { state }
    func save(_ state: ChatGPTCredentialState) throws {
        guard !failSaves else { throw ChatGPTAuthenticationError.persistenceFailed }
        self.state = state
    }
    func setFailSaves(_ value: Bool) { failSaves = value }
}

private actor ChatGPTConnectionCheckTransport: ServiceHTTPTransport {
    private var status = 200
    private var shouldSuspend = false
    private var gate: CheckedContinuation<Void, Never>?
    private var replacementGate: CheckedContinuation<Void, Never>?
    private var modelSlugs = ["fixture-model"]
    private(set) var authorizationRequests = 0
    var isWaiting: Bool { gate != nil }
    var isWaitingForReplacement: Bool { replacementGate != nil }
    func setStatus(_ value: Int) { status = value }
    func setModelSlugs(_ values: [String]) { modelSlugs = values }
    func suspendNextRequest() { shouldSuspend = true }
    func releaseRequest() { let gate = gate; self.gate = nil; gate?.resume() }
    func waitForReplacementRelease() async { await withCheckedContinuation { replacementGate = $0 } }
    func releaseReplacement() { let gate = replacementGate; replacementGate = nil; gate?.resume() }

    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        guard request.url?.absoluteString == "https://api.openai.com/v1/models" else {
            authorizationRequests += 1
            throw connectionFailure("An account endpoint was unexpectedly requested")
        }
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { gate = $0 }
        }
        let models = modelSlugs.map { ["slug": $0, "display_name": $0, "visibility": "list"] }
        let data = status == 200
            ? try JSONSerialization.data(withJSONObject: ["models": models])
            : Data(#"{"error":{"code":"invalid_token"}}"#.utf8)
        return .init(data: data, statusCode: status)
    }
}

private struct ChatGPTConnectionCheckVerifier: ChatGPTJWTSignatureVerifying {
    func verify(message: Data, signature: Data, modulus: Data, exponent: Data) throws -> Bool {
        throw connectionFailure("JWT verification is not part of a restored-token catalog check")
    }
}

private struct ChatGPTConnectionCheckCryptography: ChatGPTAuthorizationCryptography {
    func randomToken() throws -> String { throw connectionFailure("A browser sign-in must never begin in this connection check") }
    func challenge(for verifier: String) throws -> String { throw connectionFailure("A browser sign-in must never begin in this connection check") }
}

private func waitForConnectionCatalogGate(_ catalog: ChatGPTConnectionCheckTransport) async throws {
    for _ in 0..<500 {
        if await catalog.isWaiting { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw connectionFailure("Delayed catalog did not reach its fixture gate")
}

private func waitForConnectionReplacementGate(_ catalog: ChatGPTConnectionCheckTransport) async throws {
    for _ in 0..<500 {
        if await catalog.isWaitingForReplacement { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw connectionFailure("Model replacement did not reach its lifecycle fixture gate")
}

private func connectionRequire(_ condition: Bool, _ description: String) throws {
    if !condition { throw connectionFailure(description) }
}

private func connectionFailure(_ description: String) -> NSError {
    NSError(domain: "ChatGPTConnectionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
}

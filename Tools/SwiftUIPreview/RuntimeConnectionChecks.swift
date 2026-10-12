import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real observable runtime/ChatGPT models with deterministic remote receipts and isolated memory credentials.
/// No process, account browser, Keychain access, tunnel or external HTTP is started.
@MainActor
func checkDeveloperRuntimeConnection() async throws {
    var generatedTokens = Set<String>()
    for _ in 0..<10 {
        let token = try RuntimePairingToken.generate()
        try runtimeRequire(token.count == 43 && !token.contains("=") && ExecutionRemoteLimits.validPairingToken(token),
                           "Native 256-bit pairing tokens use valid unpadded base64url")
        try runtimeRequire(generatedTokens.insert(token).inserted,
                           "Each native pairing token contains fresh Security randomness")
    }
    let credentials = RuntimeCheckCredentials()
    let transport = RuntimeCheckTransport()
    let runtime = DeveloperRuntimeConnection(credentials: credentials, remoteTransport: transport)
    defer { Task { @MainActor in await runtime.disconnect() } }
    let token = String(repeating: "p", count: 64)
    await runtime.connectRemote(url: "https://runtime-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    try runtimeRequire(runtime.hasRuntime && runtime.isRemote && runtime.state.connected && runtime.remoteReachable,
                       "Verified remote snapshot establishes one connected backend")
    try runtimeRequire(!runtime.needsAccountDisconnect,
                       "An independent remote host does not depend on this phone's ChatGPT account")
    try runtimeRequire(credentials.values["developer-runtime.remote"] != nil,
                       "Verified runtime pairing persists into injected protected storage")
    let beforeSecondConnect = transport.requests.count
    await runtime.connectRemote(url: "https://other-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    try runtimeRequire(transport.requests.count == beforeSecondConnect &&
                       runtime.remoteOrigin == "https://runtime-fixture.example.invalid",
                       "Single backend rejects an overlapping remote connection")

    transport.pauseNextSnapshot = true
    let refreshing = Task { @MainActor in await runtime.refresh() }
    try await transport.waitForSnapshotGate()
    await runtime.disconnect()
    transport.releaseSnapshot()
    await refreshing.value
    try runtimeRequire(!runtime.hasRuntime && !runtime.state.connected && !runtime.remoteReachable &&
                       runtime.remoteOrigin == nil && !runtime.isConnecting && !runtime.isDisconnecting,
                       "A late refresh from the previous generation cannot resurrect a disconnected backend")

    transport.hostConnected = true
    await runtime.connectRemote(url: "https://runtime-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    transport.failStop = true
    await runtime.disconnect()
    try runtimeRequire(!runtime.hasRuntime && !runtime.state.connected && !runtime.remoteReachable &&
                       runtime.error != nil && !runtime.isDisconnecting,
                       "Remote stop failure preserves an offline local state and visible error")
    transport.failStop = false

    transport.hostConnected = true
    await runtime.connectRemote(url: "https://runtime-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    transport.pauseNextStop = true
    let stopCount = transport.stopRequests
    let firstShutdown = Task { @MainActor in await runtime.disconnect() }
    try await transport.waitForStopGate()
    let secondShutdown = Task { @MainActor in await runtime.disconnect() }
    let callsBeforeReconnect = transport.requests.count
    await runtime.connectRemote(url: "https://other-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    try runtimeRequire(runtime.isDisconnecting && transport.requests.count == callsBeforeReconnect,
                       "Connecting while shutdown is in flight cannot replace its backend")
    transport.releaseStop()
    await firstShutdown.value; await secondShutdown.value
    try runtimeRequire(transport.stopRequests == stopCount + 1 && !runtime.hasRuntime && !runtime.isDisconnecting,
                       "Concurrent disconnect callers share one stop exchange")

    transport.hostConnected = true
    await runtime.connectRemote(url: "https://runtime-fixture.example.invalid", pairingToken: token,
                                accessID: "", accessSecret: "")
    try await runtimeCheckIndependentPhoneAccount(runtime, transport: transport)
    await runtime.disconnect()
    print("Developer runtime connection checks passed: single backend, stale refresh rejection, failed remote stop, serialized shutdown and phone/host account isolation.")
}

@MainActor
private func runtimeCheckIndependentPhoneAccount(_ runtime: DeveloperRuntimeConnection,
                                               transport: RuntimeCheckTransport) async throws {
    let clientID = "oaiapp_runtimecheck_\(UUID().uuidString)"
    defer { UserDefaults.standard.removeObject(forKey: "chatgpt.selectedModel.\(clientID)") }
    let fixture = try RuntimePhoneAccountFixture(clientID: clientID)
    let session = ChatGPTSession(vault: fixture, transport: fixture, signatureVerifier: fixture,
                                authorizationCryptography: fixture)
    let account = ChatGPTConnection(session: session,
                                   client: ChatGPTResponsesClient(tokenProvider: session, catalogTransport: fixture))
    var hookCalls = 0
    var transitionRejectsPlanning = false
    account.configureBeforeAccountChange {
        hookCalls += 1
        transitionRejectsPlanning = !account.isReadyForPlanning && (try? account.requireSelectedModel()) == nil
        if runtime.needsAccountDisconnect { await runtime.disconnect() }
    }
    await account.load()
    try runtimeRequire(account.isReadyForPlanning, "Isolated phone catalog establishes its own account")
    let previousStops = transport.stopRequests
    await account.signOut()
    try runtimeRequire(transitionRejectsPlanning,
                       "The account-change hook runs with planning readiness and selected-model access disabled")
    try runtimeRequire(hookCalls == 1 && !account.isSignedIn && runtime.hasRuntime &&
                       runtime.state.connected && transport.stopRequests == previousStops,
                       "Phone sign-out invokes the lifecycle hook without stopping the host's independent registration")
}

@MainActor
private final class RuntimeCheckCredentials: ConnectionCredentialStore {
    var values: [String: String] = [:]
    func read(_ account: String) -> String? { values[account] }
    func write(_ value: String?, account: String) { values[account] = value }
}

@MainActor
private final class RuntimeCheckTransport: ServiceHTTPTransport {
    var hostConnected = true
    var failStop = false
    var pauseNextSnapshot = false
    var pauseNextStop = false
    private(set) var requests: [URLRequest] = []
    private(set) var stopRequests = 0
    private var snapshotGate: CheckedContinuation<Void, Never>?
    private var snapshotObserver: CheckedContinuation<Void, Never>?
    private var stopGate: CheckedContinuation<Void, Never>?
    private var stopObserver: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        requests.append(request)
        switch request.url?.path {
        case "/v1/execution/snapshot":
            let response = try snapshot(connected: hostConnected)
            if pauseNextSnapshot {
                pauseNextSnapshot = false
                await withCheckedContinuation { continuation in
                    snapshotGate = continuation
                    let observer = snapshotObserver; snapshotObserver = nil; observer?.resume()
                }
            }
            // Capture before the gate to model a genuinely stale receipt from the old host.
            return response
        case "/v1/execution/stop":
            stopRequests += 1
            if pauseNextStop {
                pauseNextStop = false
                await withCheckedContinuation { continuation in
                    stopGate = continuation
                    let observer = stopObserver; stopObserver = nil; observer?.resume()
                }
            }
            if failStop { return .init(data: Data("{}".utf8), statusCode: 503) }
            hostConnected = false
            return try snapshot(connected: false)
        default: throw runtimeFailure("Unexpected runtime route in isolated transport")
        }
    }

    func waitForSnapshotGate() async throws {
        if snapshotGate != nil { return }
        let deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            let observer = self?.snapshotObserver; self?.snapshotObserver = nil; observer?.resume()
        }
        defer { deadline.cancel() }
        await withCheckedContinuation { snapshotObserver = $0 }
        guard snapshotGate != nil else { throw runtimeFailure("Delayed snapshot fixture did not reach its gate") }
    }
    func releaseSnapshot() {
        let continuation = snapshotGate; snapshotGate = nil; continuation?.resume()
    }
    func waitForStopGate() async throws {
        if stopGate != nil { return }
        let deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            let observer = self?.stopObserver; self?.stopObserver = nil; observer?.resume()
        }
        defer { deadline.cancel() }
        await withCheckedContinuation { stopObserver = $0 }
        guard stopGate != nil else { throw runtimeFailure("Delayed shutdown fixture did not reach its gate") }
    }
    func releaseStop() {
        let continuation = stopGate; stopGate = nil; continuation?.resume()
    }
    private func snapshot(connected: Bool) throws -> ServiceHTTPResponse {
        let value = ExecutionSnapshot(connected: connected, developers: [], records: [], blocker: nil)
        return .init(data: try JSONEncoder().encode(value), statusCode: 200)
    }
}

private actor RuntimePhoneAccountFixture: ChatGPTCredentialVault, ServiceHTTPTransport,
                                         ChatGPTJWTSignatureVerifying, ChatGPTAuthorizationCryptography {
    private var state: ChatGPTCredentialState
    init(clientID: String) throws {
        let registration: [String: Any] = [
            "clientID": clientID, "subject": "runtime-fixture-subject", "issuer": "https://auth.openai.com",
            "tokens": ["accessToken": "runtime-fixture-access", "refreshToken": "runtime-fixture-refresh",
                       "idToken": "runtime-fixture-restored-identity", "scopes": ["openid", "offline_access", "chatgpt.tokens.use.direct"],
                       "expiresAt": Date().addingTimeInterval(3_600).timeIntervalSinceReferenceDate]]
        let saved = try JSONDecoder().decode(ChatGPTRegistration.self, from: JSONSerialization.data(withJSONObject: registration))
        state = .init(hostID: "urn:uuid:\(UUID().uuidString.lowercased())", registrations: [saved], activeClientID: clientID)
    }
    func load() -> ChatGPTCredentialState? { state }
    func save(_ state: ChatGPTCredentialState) { self.state = state }
    func send(_ request: URLRequest) throws -> ServiceHTTPResponse {
        guard request.url?.absoluteString == "https://api.openai.com/v1/models" else {
            // Revocation is deliberately unconfirmed; no account endpoint reaches a network.
            throw runtimeFailure("Account endpoint is unavailable in the isolated phone fixture")
        }
        return .init(data: Data(#"{"models":[{"slug":"runtime-fixture-model","display_name":"Runtime fixture","visibility":"list"}]}"#.utf8), statusCode: 200)
    }
    nonisolated func randomToken() throws -> String { throw runtimeFailure("Browser sign-in must never start in the phone fixture") }
    nonisolated func challenge(for verifier: String) throws -> String { throw runtimeFailure("PKCE is not used by restored fixture credentials") }
    nonisolated func verify(message: Data, signature: Data, modulus: Data, exponent: Data) throws -> Bool {
        throw runtimeFailure("Restored fixture credentials must never invoke JWT verification")
    }
}

private func runtimeRequire(_ condition: Bool, _ description: String) throws {
    if !condition { throw runtimeFailure(description) }
}
private func runtimeFailure(_ description: String) -> NSError {
    NSError(domain: "RuntimeConnectionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
}

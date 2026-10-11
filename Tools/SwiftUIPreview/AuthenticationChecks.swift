import Foundation
import CryptoKit
import Security
import Network
import EngineeringCore

/// Real Apple crypto, protected storage and local HTTP; never opens account login or uses production credentials.
@MainActor
func checkChatGPTAuthentication() async throws {
    let cryptography = ChatGPTAppleCryptography()
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    try authRequire(cryptography.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC7636 SHA256 PKCE vector")
    let one = try cryptography.randomToken(); let two = try cryptography.randomToken()
    try authRequire(one.count == 43 && two.count == 43 && one != two, "Security creates fresh 256-bit base64url secrets")

    var keyError: Unmanaged<CFError>?
    let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2_048]
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &keyError),
          let publicKey = SecKeyCopyPublicKey(privateKey),
          let publicData = SecKeyCopyExternalRepresentation(publicKey, &keyError) as Data? else { throw authFailure("Create ephemeral RSA key") }
    let message = Data("Engineering Studio isolated authentication check".utf8)
    guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &keyError) as Data? else { throw authFailure("Sign fixture with Security") }
    let pair = try authRSAComponents(publicData)
    let signatureVerifier = ChatGPTAppleSignatureVerifier()
    try authRequire(try signatureVerifier.verify(message: message, signature: signature, modulus: pair.0, exponent: pair.1), "Real Security RS256 signature verifies JWK components")
    try authRequire(try !signatureVerifier.verify(message: Data("different".utf8), signature: signature, modulus: pair.0, exponent: pair.1), "Modified RS256 message is rejected")

    let testService = "dev.kmsh.engineeringstudio.auth-check.\(UUID().uuidString)"
    let vault = ChatGPTKeychainVault(service: testService, account: "isolated-fixture")
    do {
        try authRequire(try await vault.load() == nil, "Isolated Keychain namespace starts empty")
        let first = ChatGPTCredentialState(hostID: "urn:uuid:\(UUID().uuidString.lowercased())")
        try await vault.save(first)
        try authRequire(try await vault.load()?.hostID == first.hostID, "Protected Keychain record roundtrip")
        var replacement = first; replacement.activeClientID = "fixture-client"
        try await vault.save(replacement)
        try authRequire(try await vault.load()?.activeClientID == "fixture-client", "Protected record replaces atomically")
        try await vault.delete()
        try authRequire(try await vault.load() == nil, "Fixture Keychain item is removed")
    } catch {
        try? await vault.delete()
        throw error
    }

    let listener = ChatGPTLoopbackListener(timeout: .seconds(10))
    let port = try await listener.start()
    defer { listener.cancel() }
    let session = ChatGPTSession(vault: AuthenticationMemoryVault(), signatureVerifier: ChatGPTAppleSignatureVerifier(), authorizationCryptography: cryptography)
    let attempt = try await session.beginAuthorization(port: port)
    listener.configure(attempt)
    let state = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.first(where: { $0.name == "state" })!.value!
    let invalid = "GET /auth/callback?code=fixture&state=wrong HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
    let rejected = try await authenticationLoopbackSend(invalid, port: port)
    try authRequire(rejected.hasPrefix("HTTP/1.1 400"), "Unrelated callback does not consume listener")
    let valid = "GET /auth/callback?code=fixture&state=\(state)&client_id=fixture-client HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
    async let received = listener.waitForCallback()
    let accepted = try await authenticationLoopbackSend(valid, port: port)
    let callback = try await received
    try authRequire(accepted.hasPrefix("HTTP/1.1 200") && callback.host == "127.0.0.1" && callback.port == Int(port), "NWListener receives strict IPv4 HTTP callback")
    await session.cancelAuthorization()

    let canceled = ChatGPTLoopbackListener(timeout: .seconds(10))
    _ = try await canceled.start()
    canceled.cancel()
    do { _ = try await canceled.waitForCallback(); throw authFailure("Canceled listener must throw") }
    catch ChatGPTAuthenticationError.canceled { }

    let expired = ChatGPTLoopbackListener(timeout: .milliseconds(100))
    _ = try await expired.start()
    do { _ = try await expired.waitForCallback(); throw authFailure("Listener deadline must throw") }
    catch ChatGPTAuthenticationError.authorizationExpired { }
    print("ChatGPT authentication checks passed: real Security RSA signatures, CryptoKit PKCE, isolated Keychain roundtrip, strict loopback HTTP, cancellation and deadline.")
}

private actor AuthenticationMemoryVault: ChatGPTCredentialVault {
    private var value: ChatGPTCredentialState?
    func load() -> ChatGPTCredentialState? { value }
    func save(_ state: ChatGPTCredentialState) { value = state }
}

/// Reads Security's PKCS#1 public representation; this parser is for the ephemeral test key only.
private func authRSAComponents(_ data: Data) throws -> (Data, Data) {
    let bytes = Array(data); var index = 0
    func length() throws -> Int {
        guard index < bytes.count else { throw authFailure("Truncated RSA representation") }
        let first = bytes[index]; index += 1
        if first < 128 { return Int(first) }
        let count = Int(first & 0x7f)
        guard count > 0 && count <= 4 && index + count <= bytes.count else { throw authFailure("Invalid DER length") }
        var result = 0
        for _ in 0..<count { result = result * 256 + Int(bytes[index]); index += 1 }
        return result
    }
    guard bytes.first == 0x30 else { throw authFailure("RSA sequence") }; index += 1
    _ = try length()
    func integer() throws -> Data {
        guard index < bytes.count, bytes[index] == 2 else { throw authFailure("RSA integer") }; index += 1
        let count = try length()
        guard count > 0 && index + count <= bytes.count else { throw authFailure("RSA integer bounds") }
        defer { index += count }
        return Data(bytes[index..<index + count].drop(while: { $0 == 0 }))
    }
    return (try integer(), try integer())
}

@MainActor
private func authenticationLoopbackSend(_ request: String, port: UInt16) async throws -> String {
    let exchange = AuthenticationLoopbackExchange()
    return try await exchange.send(request, port: port)
}

@MainActor
private final class AuthenticationLoopbackExchange {
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeout: Task<Void, Never>?
    private var received = Data()

    func send(_ request: String, port: UInt16) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.connection = connection
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        connection.send(content: Data(request.utf8), completion: .contentProcessed { [weak self] error in
                            Task { @MainActor in
                                guard let self else { return }
                                if error != nil { self.finish(.failure(authFailure("Send loopback fixture"))) }
                                else { self.read() }
                            }
                        })
                    case .failed: self.finish(.failure(authFailure("Connect loopback fixture")))
                    default: break
                    }
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finish(.failure(authFailure("Loopback fixture deadline")))
            }
            connection.start(queue: .main)
        }
    }

    private func read() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                if let data { self.received.append(data) }
                if error != nil { self.finish(.failure(authFailure("Receive loopback fixture"))) }
                else if complete { self.finish(.success(String(decoding: self.received, as: UTF8.self))) }
                else { self.read() }
            }
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        let continuation = self.continuation; self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        continuation?.resume(with: result)
    }
}

private func authRequire(_ condition: Bool, _ description: String) throws {
    if !condition { throw authFailure(description) }
}
private func authFailure(_ description: String) -> NSError { NSError(domain: "ChatGPTAuthenticationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: description]) }

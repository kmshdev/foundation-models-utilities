/// Atomic replacement of the complete protected record is required for rotating refresh tokens.
public protocol ChatGPTCredentialVault: Sendable {
    func load() async throws -> ChatGPTCredentialState?
    func save(_ state: ChatGPTCredentialState) async throws
}

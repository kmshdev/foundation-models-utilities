import StudioServices

/// The startup fixture exposes no saved provider or executor credential.
@MainActor
final class StartupMemoryCredentials: ConnectionCredentialStore {
    private(set) var readCount = 0
    func read(_ account: String) -> String? { readCount += 1; return nil }
    func write(_ value: String?, account: String) { }
}

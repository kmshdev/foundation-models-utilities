@testable import StudioServices

@MainActor
final class ProviderCheckLegacyCredentials: ConnectionCredentialStore {
    private(set) var values = ["github": "isolated-legacy-github", "linear": "isolated-legacy-linear"]
    private(set) var writeCount = 0

    func read(_ account: String) -> String? { values[account] }
    func write(_ value: String?, account: String) {
        writeCount += 1
        values[account] = value
    }
}

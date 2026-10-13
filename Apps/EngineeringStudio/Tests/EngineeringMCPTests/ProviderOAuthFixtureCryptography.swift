import EngineeringMCP

struct ProviderOAuthFixtureCryptography: ProviderOAuthCryptography {
    func randomToken() throws -> String { String(repeating: "v", count: 64) }
    func challenge(for verifier: String) throws -> String { "fixture-S256-challenge" }
}

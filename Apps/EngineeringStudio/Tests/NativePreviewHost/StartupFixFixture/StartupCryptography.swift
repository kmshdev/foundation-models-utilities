import EngineeringCore

/// No browser authorization is part of a fixture's empty-account restoration.
struct StartupCryptography: ChatGPTAuthorizationCryptography {
    func randomToken() throws -> String { throw ChatGPTAuthenticationError.canceled }
    func challenge(for verifier: String) throws -> String { throw ChatGPTAuthenticationError.canceled }
}

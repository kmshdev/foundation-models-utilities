import EngineeringCore

@MainActor
enum ChatGPTAuthenticationFactory {
    static func makeSession() -> ChatGPTSession {
        ChatGPTSession(vault: ChatGPTKeychainVault(), signatureVerifier: ChatGPTAppleSignatureVerifier(),
                       authorizationCryptography: ChatGPTAppleCryptography())
    }
}

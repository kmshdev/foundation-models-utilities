import EngineeringServices
import EngineeringCore

@MainActor
package enum ChatGPTAuthenticationFactory {
    package static func makeSession() -> ChatGPTSession {
        ChatGPTSession(vault: ChatGPTKeychainVault(), signatureVerifier: ChatGPTAppleSignatureVerifier(),
                       authorizationCryptography: ChatGPTAppleCryptography())
    }
}

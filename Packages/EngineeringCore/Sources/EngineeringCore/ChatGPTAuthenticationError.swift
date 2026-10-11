import Foundation

public enum ChatGPTAuthenticationError: Error, Sendable, Equatable, LocalizedError {
    case notSignedIn, planUsageDisabled, authorizationInProgress, invalidCallback, stateMismatch
    case registrationIncomplete, identityMismatch, invalidIDToken, invalidTokenResponse
    case authorizationDenied, authorizationExpired, canceled, persistenceFailed
    case oauth(code: String, status: Int, requestID: String?)
    case http(status: Int, requestID: String?)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "Continue with ChatGPT to connect your account."
        case .planUsageDisabled: "ChatGPT plan access is disabled for this account. Enable access in ChatGPT settings."
        case .authorizationInProgress: "A ChatGPT sign-in is already in progress."
        case .invalidCallback, .stateMismatch: "The sign-in callback did not match this authorization attempt."
        case .registrationIncomplete: "ChatGPT did not return a valid registered client ID."
        case .identityMismatch: "The returned ChatGPT identity differs from the selected account."
        case .invalidIDToken: "The ChatGPT identity token could not be verified."
        case .invalidTokenResponse: "ChatGPT returned an incomplete token response."
        case .authorizationDenied: "ChatGPT sign-in was declined."
        case .authorizationExpired: "ChatGPT sign-in timed out. Please try again."
        case .canceled: "ChatGPT sign-in was canceled."
        case .persistenceFailed: "Credentials could not be saved securely. Please try again."
        case .oauth(let code, let status, _): "ChatGPT authentication failed (\(code), HTTP \(status))."
        case .http(let status, _): "ChatGPT authentication returned HTTP \(status). Try again later."
        }
    }

    public var requiresReauthorization: Bool {
        guard case .oauth(let code, _, _) = self else { return false }
        return ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code)
    }
}

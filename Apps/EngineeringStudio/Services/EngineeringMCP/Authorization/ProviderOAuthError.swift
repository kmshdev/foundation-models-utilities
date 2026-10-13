import Foundation

/// Deliberately redacted: provider responses, callback URLs and credentials are never error messages.
public enum ProviderOAuthError: Error, LocalizedError, Sendable, Equatable {
    case authorizationInProgress
    case notConfigured
    case notAuthorized
    case canceled
    case authorizationExpired
    case invalidCallback
    case authorizationDenied
    case invalidMetadata
    case registrationFailed
    case tokenRejected
    case scopeRejected
    case refreshExpired
    case configurationChanged
    case secureStorageUnavailable
    case networkUnavailable
    case presentationUnavailable

    public var errorDescription: String? {
        switch self {
        case .authorizationInProgress: "A connection operation is already running."
        case .notConfigured: "Add this app’s GitHub client ID and client secret before signing in."
        case .notAuthorized: "Sign in to connect this provider."
        case .canceled: "Sign-in was canceled. Your previous connection was retained."
        case .authorizationExpired: "Sign-in expired. Try connecting again."
        case .invalidCallback: "The sign-in callback did not match this connection."
        case .authorizationDenied: "The provider did not authorize this connection."
        case .invalidMetadata: "The provider’s authorization settings could not be verified."
        case .registrationFailed: "The provider could not register this native client."
        case .tokenRejected: "The provider did not return a valid access token."
        case .scopeRejected: "The provider grant did not match the requested read-only access."
        case .refreshExpired: "This connection needs a new sign-in."
        case .configurationChanged: "The saved grant belongs to a different GitHub app. Sign in again."
        case .secureStorageUnavailable: "The connection could not be saved securely on this device."
        case .networkUnavailable: "The provider could not be reached. Try again."
        case .presentationUnavailable: "Open an app window before starting sign-in."
        }
    }
}

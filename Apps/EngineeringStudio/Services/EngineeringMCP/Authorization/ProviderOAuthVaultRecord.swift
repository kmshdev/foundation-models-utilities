/// Each record is protected storage; configuration and the active grant are replaced separately.
public enum ProviderOAuthVaultRecord: String, Sendable {
    case configuration
    case grant
    case pendingRegistration
}

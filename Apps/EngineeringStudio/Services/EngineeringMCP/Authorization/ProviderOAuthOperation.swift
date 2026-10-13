import Foundation

struct ProviderOAuthOperation: Sendable {
    let id = UUID()
    let transaction = ProviderOAuthStorageTransaction()
}

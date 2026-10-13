import Foundation

/// Allocate the native callback before registration; cancel only the matching browser attempt.
public protocol ProviderOAuthBrowser: Sendable {
    func prepareCallback(for provider: MCPProvider) async throws -> ProviderOAuthBrowserAttempt
    func present(authorizationURL: URL, attempt: ProviderOAuthBrowserAttempt) async throws -> URL
    func cancel(attemptID: UUID) async
}

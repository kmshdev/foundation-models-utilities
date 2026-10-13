import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ProviderOAuthHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ProviderOAuthHTTPResponse
}

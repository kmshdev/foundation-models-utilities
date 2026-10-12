import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ServiceHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse
}

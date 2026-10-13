import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ChatGPTResponsesStreamingTransport: Sendable {
    func open(_ request: URLRequest) async throws -> ChatGPTResponsesHTTPStream
}

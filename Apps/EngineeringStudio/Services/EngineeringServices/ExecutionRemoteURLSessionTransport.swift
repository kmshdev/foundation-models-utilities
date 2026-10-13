import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Each exchange has its own byte budget and refuses redirects, cookies and implicit account login.
public struct ExecutionRemoteURLSessionTransport: ServiceHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let exchange = ExecutionRemoteExchange()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in exchange.start(request, continuation: continuation) }
        } onCancel: { exchange.cancel() }
    }
}

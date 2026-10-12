import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral sessions avoid persisting authorization; refusing redirects prevents credential forwarding.
public final class URLSessionServiceTransport: ServiceHTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceClientError.invalidResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        return ServiceHTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}

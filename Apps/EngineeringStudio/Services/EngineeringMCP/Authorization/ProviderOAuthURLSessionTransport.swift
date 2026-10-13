import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// No redirects, cookies or cache on credential requests. Each request has a finite network budget.
public final class ProviderOAuthURLSessionTransport: ProviderOAuthHTTPTransport, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        // Use an immutable delegate object; constructing this service performs no network I/O.
        session = URLSession(configuration: configuration, delegate: ProviderOAuthNoRedirectDelegate(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> ProviderOAuthHTTPResponse {
        guard request.url?.scheme == "https" else { throw ProviderOAuthError.invalidMetadata }
        #if os(Linux)
        let (data, response) = try await session.data(for: request)
        guard data.count <= 262_144, let response = response as? HTTPURLResponse else {
            throw ProviderOAuthError.invalidMetadata
        }
        return .init(statusCode: response.statusCode, data: data)
        #else
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= 262_144 else { throw ProviderOAuthError.invalidMetadata }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262_144 else { throw ProviderOAuthError.invalidMetadata }
            data.append(byte)
        }
        return .init(statusCode: response.statusCode, data: data)
        #endif
    }
}

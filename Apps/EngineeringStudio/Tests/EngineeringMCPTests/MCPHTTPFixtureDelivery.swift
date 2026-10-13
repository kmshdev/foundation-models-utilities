#if !os(Linux)
import Foundation

/// URLProtocol itself forbids Sendable conformance. This fixture captures its
/// already-installed client and protocol references immutably. Only the single
/// loading task invokes these Foundation callbacks; subclass mutable state stays
/// behind Mutex and fixture response state stays on its actor.
final class MCPHTTPFixtureDelivery: @unchecked Sendable {
    private let owner: URLProtocol
    private let client: (any URLProtocolClient)?

    init(owner: URLProtocol) {
        self.owner = owner
        client = owner.client
    }

    func succeed(response: HTTPURLResponse, data: Data) {
        client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(owner, didLoad: data) }
        client?.urlProtocolDidFinishLoading(owner)
    }

    func fail(_ error: any Error) {
        client?.urlProtocol(owner, didFailWithError: error)
    }
}
#endif

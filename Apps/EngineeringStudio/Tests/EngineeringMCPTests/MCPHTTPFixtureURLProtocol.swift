#if !os(Linux)
import Foundation
import Synchronization

/// URLProtocol's callbacks run outside actor isolation. Registry/task mutation is
/// protected by Mutex; response state belongs to MCPHTTPFixture. Each test uses
/// an immutable fixture, and Foundation's URLProtocolClient receives callbacks only
/// from this instance's single loading task. The HTTP suite is serialized, and
/// no global URLProtocol session registration occurs.
final class MCPHTTPFixtureURLProtocol: URLProtocol {
    static let marker = "X-Engineering-MCP-Fixture"
    private static let fixtures = Mutex<[String: MCPHTTPFixture]>([:])
    private let loadingTask = Mutex<Task<Void, Never>?>(nil)

    static func register(_ fixture: MCPHTTPFixture, id: String) {
        fixtures.withLock { $0[id] = fixture }
    }

    static func unregister(id: String) {
        _ = fixtures.withLock { $0.removeValue(forKey: id) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // This class is installed only in the fixture's URLSession configuration.
        // Capture every request so a missing marker fails locally instead of
        // allowing a test credential or malformed request onto the real network.
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let fixture = Self.fixtures.withLock { fixtures in
            if let id = request.value(forHTTPHeaderField: Self.marker) { return fixtures[id] }
            // URLProtocol can see the request before URLSession merges configuration
            // headers. The serialized suite has exactly one registered fixture;
            // ambiguous or missing registrations fail locally, never on the network.
            return fixtures.count == 1 ? fixtures.values.first : nil
        }
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: MCPFixtureError.invalidArguments)
            return
        }
        let request = request
        let delivery = MCPHTTPFixtureDelivery(owner: self)
        let task = Task { @concurrent in
            do {
                let (response, data) = try await fixture.response(for: request)
                try Task.checkCancellation()
                delivery.succeed(response: response, data: data)
            } catch {
                delivery.fail(error)
            }
        }
        loadingTask.withLock { $0 = task }
    }

    override func stopLoading() {
        loadingTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }
}
#endif

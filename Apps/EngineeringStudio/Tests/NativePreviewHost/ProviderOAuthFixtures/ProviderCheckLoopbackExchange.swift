import Foundation
import Network

/// Real native HTTP restricted to the listener's isolated IPv4 loopback port.
@MainActor
final class ProviderCheckLoopbackExchange {
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeout: Task<Void, Never>?
    private var received = Data()

    func send(_ request: String, port: UInt16) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.connection = connection
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        connection.send(content: Data(request.utf8), completion: .contentProcessed { [weak self] error in
                            Task { @MainActor in
                                guard let self else { return }
                                if error != nil { self.finish(.failure(ProviderCheckFailure.assertion("Loopback fixture send failed"))) }
                                else { self.read() }
                            }
                        })
                    case .failed:
                        self.finish(.failure(ProviderCheckFailure.assertion("Loopback fixture connection failed")))
                    default: break
                    }
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.finish(.failure(ProviderCheckFailure.assertion("Loopback fixture response timed out")))
            }
            connection.start(queue: .main)
        }
    }

    private func read() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                if let data { self.received.append(data) }
                if error != nil || self.received.count > 32_768 {
                    self.finish(.failure(ProviderCheckFailure.assertion("Loopback fixture response was invalid")))
                } else if complete {
                    self.finish(.success(String(decoding: self.received, as: UTF8.self)))
                } else {
                    self.read()
                }
            }
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        let pending = continuation
        continuation = nil
        timeout?.cancel()
        timeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pending?.resume(with: result)
    }
}

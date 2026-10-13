import EngineeringServices
import Foundation
import Network
import EngineeringCore

/// The host's existing runtime is reachable only through IPv4 loopback. A separately configured
/// Cloudflare Tunnel may publish it; this class never opens a public listener or transfers model credentials.
@MainActor
package final class ExecutionLoopbackServer {
    private let pairingToken: String
    private let handler: any ExecutionRemoteHandler
    private var router: ExecutionRemoteRouter?
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, any Error>?
    private var readyDeadline: Task<Void, Never>?
    private var listeningPort: UInt16?
    private var generation = UUID()
    private var connections: [UUID: NWConnection] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var operations: [UUID: Task<Void, Never>] = [:]

    package init(pairingToken: String, handler: any ExecutionRemoteHandler) {
        self.pairingToken = pairingToken
        self.handler = handler
    }

    package func start(port: UInt16 = 0) async throws -> UInt16 {
        if let listeningPort { return listeningPort }
        guard listener == nil else { throw ExecutionRemoteError.rejected }
        router = try ExecutionRemoteRouter(pairingToken: pairingToken, handler: handler)
        let parameters = NWParameters.tcp
        let requestedPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: requestedPort)
        let listener = try NWListener(using: parameters, on: requestedPort)
        self.listener = listener
        let activeGeneration = UUID(); generation = activeGeneration
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == activeGeneration else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port?.rawValue else { self.stop(); return }
                    self.listeningPort = port
                    self.readyDeadline?.cancel(); self.readyDeadline = nil
                    let continuation = self.ready; self.ready = nil; continuation?.resume(returning: port)
                case .failed, .cancelled: self.stop()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == activeGeneration else { connection.cancel(); return }
                self.accept(connection)
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                readyDeadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    self?.stop()
                }
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
    }

    /// Stops only the bridge listener. Stopping developer work uses the authenticated /stop operation.
    package func stop() {
        generation = UUID()
        let continuation = ready; ready = nil
        readyDeadline?.cancel(); readyDeadline = nil
        listeningPort = nil; router = nil
        let listener = self.listener; self.listener = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel()
        for id in Array(connections.keys) { close(id) }
        continuation?.resume(throwing: ExecutionRemoteError.unavailable)
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, connections.count < ExecutionRemoteLimits.maximumConnections else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: Task { @MainActor in self?.close(id) }
            default: break
            }
        }
        connection.start(queue: .main)
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(ExecutionRemoteLimits.requestTimeoutSeconds)) } catch { return }
            self?.close(id)
        }
        read(connection, id: id, buffer: Data())
    }

    private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                guard error == nil else { self.close(id); return }
                var bytes = buffer; if let data { bytes.append(data) }
                do {
                    if let request = try ExecutionRemoteRequest.parse(bytes), let router = self.router {
                        if request.path == "/v1/execution/publish", request.isAuthorized(pairingToken: self.pairingToken) {
                            // Slow request framing retains the short budget. Only a complete, authenticated
                            // publication receives enough time for multiple bounded GitHub operations.
                            self.deadlines.removeValue(forKey: id)?.cancel()
                            self.deadlines[id] = Task { [weak self] in
                                do { try await Task.sleep(for: .seconds(ExecutionRemoteLimits.publicationTimeoutSeconds)) } catch { return }
                                self?.close(id)
                            }
                        }
                        self.operations[id] = Task { [weak self] in
                            let response = await router.respond(to: request)
                            guard let self, self.connections[id] != nil, !Task.isCancelled else { return }
                            self.reply(connection, id: id, response: response)
                        }
                    } else if complete { self.reply(connection, id: id, response: ExecutionRemoteRouter.failure(.malformedRequest)) }
                    else { self.read(connection, id: id, buffer: bytes) }
                } catch let error as ExecutionRemoteError {
                    self.reply(connection, id: id, response: ExecutionRemoteRouter.failure(error))
                } catch { self.close(id) }
            }
        }
    }

    private func reply(_ connection: NWConnection, id: UUID, response: ServiceHTTPResponse) {
        let header = "HTTP/1.1 \(response.statusCode) Response\r\nContent-Type: application/json\r\nContent-Length: \(response.data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var bytes = Data(header.utf8); bytes.append(response.data)
        connection.send(content: bytes, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        operations.removeValue(forKey: id)?.cancel()
        if let connection = connections.removeValue(forKey: id) {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }
}

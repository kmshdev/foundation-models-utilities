import Foundation
import Network
import EngineeringCore

/// Binds only IPv4 loopback. All lifecycle and continuation ownership stays on MainActor.
@MainActor
final class ChatGPTLoopbackListener {
    private let timeoutDuration: Duration
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, any Error>?
    private var callback: CheckedContinuation<URL, any Error>?
    private var result: Result<URL, any Error>?
    private var expectedState: String?
    private var port: UInt16?
    private var connections: [UUID: NWConnection] = [:]
    private var timeout: Task<Void, Never>?

    init(timeout: Duration = .seconds(300)) { timeoutDuration = timeout }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let value = self.listener?.port?.rawValue else { self.finish(.failure(ChatGPTAuthenticationError.invalidCallback)); return }
                    self.port = value
                    let continuation = self.ready; self.ready = nil; continuation?.resume(returning: value)
                case .failed, .cancelled:
                    self.finish(.failure(ChatGPTAuthenticationError.canceled))
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: self?.timeoutDuration ?? .seconds(300)) } catch { return }
                self?.finish(.failure(ChatGPTAuthenticationError.authorizationExpired))
            }
            listener.start(queue: .main)
        }
    }

    func configure(_ attempt: ChatGPTAuthorizationAttempt) {
        expectedState = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value
    }

    func waitForCallback() async throws -> URL {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { callback = $0 }
    }

    func cancel() { finish(.failure(ChatGPTAuthenticationError.canceled)) }

    private func accept(_ connection: NWConnection) {
        guard result == nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        read(connection, id: id, buffer: Data())
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }

    private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var bytes = buffer; if let data { bytes.append(data) }
                guard bytes.count <= 16_384, error == nil else { self.close(id); return }
                if let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) {
                    let header = Data(bytes[..<boundary.upperBound])
                    guard let port = self.port, let state = self.expectedState,
                          let url = try? ChatGPTLoopbackRequest.callbackURL(header: header, port: port, expectedState: state) else {
                        self.reply(connection, id: id, status: "400 Bad Request", body: "This callback did not match the pending sign-in.")
                        return
                    }
                    self.reply(connection, id: id, status: "200 OK", body: "Sign-in received. You can return to Engineering Studio.")
                    // Let the reply leave before closing all listener connections.
                    self.finish(.success(url), completingConnection: id)
                } else if complete { self.close(id) }
                else { self.read(connection, id: id, buffer: bytes) }
            }
        }
    }

    private func reply(_ connection: NWConnection, id: UUID, status: String, body: String) {
        let text = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }

    private func finish(_ value: Result<URL, any Error>, completingConnection: UUID? = nil) {
        guard result == nil else { return }
        result = value
        timeout?.cancel(); timeout = nil
        let ready = self.ready; self.ready = nil
        if let ready {
            switch value { case .failure(let error): ready.resume(throwing: error); case .success: ready.resume(throwing: ChatGPTAuthenticationError.invalidCallback) }
        }
        let callback = self.callback; self.callback = nil; callback?.resume(with: value)
        let listener = self.listener; self.listener = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel()
        for id in Array(connections.keys) where id != completingConnection { close(id) }
    }
}

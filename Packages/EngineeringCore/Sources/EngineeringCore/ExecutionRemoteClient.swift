import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Swift client for the already configured host. HTTPS and fixed routes prevent credential forwarding to arbitrary URLs.
public struct ExecutionRemoteClient: Sendable {
    private let baseURL: URL
    private let pairingToken: String
    private let access: ExecutionRemoteAccessCredential?
    private let transport: any ServiceHTTPTransport

    public init(baseURL: URL, pairingToken: String, access: ExecutionRemoteAccessCredential? = nil,
                transport: any ServiceHTTPTransport = ExecutionRemoteURLSessionTransport()) throws {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", ExecutionRemoteLimits.validPairingToken(pairingToken) else {
            throw ExecutionRemoteError.invalidConfiguration
        }
        self.baseURL = baseURL
        self.pairingToken = pairingToken
        self.access = access
        self.transport = transport
    }

    public func snapshot() async throws -> ExecutionSnapshot { try await request("snapshot", body: nil) }
    public func dispatch(_ input: ExecutionRemoteDispatch) async throws -> ExecutionSnapshot {
        try await request("dispatch", body: JSONEncoder().encode(input))
    }
    public func cancel(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        try await request("cancel", body: JSONEncoder().encode(key))
    }
    public func resume(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        try await request("resume", body: JSONEncoder().encode(key))
    }
    public func stop() async throws -> ExecutionSnapshot { try await request("stop", body: Data()) }
    public func restart() async throws -> ExecutionSnapshot { try await request("restart", body: Data()) }
    /// Only task identity is sent. Repository credentials and git evidence remain owned by the host.
    public func publish(_ key: ExecutionTaskKey) async throws -> ExecutionPullRequestReceipt {
        let receipt: ExecutionPullRequestReceipt = try await request("publish", body: JSONEncoder().encode(key))
        guard ExecutionRemoteReceiptValidation.matches(receipt, key: key) else { throw ExecutionRemoteError.invalidResponse }
        return receipt
    }

    private func request<Result: Decodable>(_ route: String, body: Data?) async throws -> Result {
        try Task.checkCancellation()
        guard (body?.count ?? 0) <= ExecutionRemoteLimits.maximumBodyBytes else { throw ExecutionRemoteError.oversizedRequest }
        let url = baseURL.appending(path: "v1/execution/\(route)")
        var request = URLRequest(url: url, timeoutInterval: route == "publish" ? 110 : 15)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(pairingToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        }
        if let access {
            request.setValue(access.clientID, forHTTPHeaderField: "CF-Access-Client-ID")
            request.setValue(access.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        let response: ServiceHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as ExecutionRemoteError { throw error }
        catch { throw ExecutionRemoteError.unavailable }
        try Task.checkCancellation()
        guard response.data.count <= ExecutionRemoteLimits.maximumResponseBytes else { throw ExecutionRemoteError.oversizedResponse }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw ExecutionRemoteError.unauthorized
        case 400: throw ExecutionRemoteError.malformedRequest
        case 404, 405: throw ExecutionRemoteError.unsupportedRoute
        case 408, 504: throw ExecutionRemoteError.timedOut
        case 413: throw ExecutionRemoteError.oversizedRequest
        case 409: throw ExecutionRemoteError.rejected
        default: throw ExecutionRemoteError.unavailable
        }
        do { return try JSONDecoder().decode(Result.self, from: response.data) }
        catch { throw ExecutionRemoteError.invalidResponse }
    }
}

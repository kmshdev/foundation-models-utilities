import EngineeringCore
import Foundation

public struct ExecutionRemoteRouter: Sendable {
    private let pairingToken: String
    private let handler: any ExecutionRemoteHandler

    public init(pairingToken: String, handler: any ExecutionRemoteHandler) throws {
        guard ExecutionRemoteLimits.validPairingToken(pairingToken) else { throw ExecutionRemoteError.invalidConfiguration }
        self.pairingToken = pairingToken
        self.handler = handler
    }

    public func respond(to request: ExecutionRemoteRequest) async -> ServiceHTTPResponse {
        guard request.isAuthorized(pairingToken: pairingToken) else { return Self.failure(.unauthorized) }
        do {
            try Task.checkCancellation()
            let snapshot: ExecutionSnapshot
            switch request.path {
            case "/v1/execution/snapshot": snapshot = try await handler.snapshot()
            case "/v1/execution/dispatch":
                let input: ExecutionRemoteDispatch = try Self.decode(request.body)
                guard !input.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      input.outcome.utf8.count <= 32_768, (1...64).contains(input.plan.tasks.count) else {
                    throw ExecutionRemoteError.malformedRequest
                }
                snapshot = try await handler.dispatch(input)
            case "/v1/execution/cancel": snapshot = try await handler.cancel(Self.decode(request.body))
            case "/v1/execution/resume": snapshot = try await handler.resume(Self.decode(request.body))
            case "/v1/execution/stop": snapshot = try await handler.stop()
            case "/v1/execution/restart": snapshot = try await handler.restart()
            case "/v1/execution/publish":
                let key: ExecutionTaskKey = try Self.decode(request.body)
                let receipt = try await handler.publish(key)
                guard ExecutionRemoteReceiptValidation.matches(receipt, key: key) else { throw ExecutionRemoteError.rejected }
                return try Self.success(receipt)
            default: throw ExecutionRemoteError.unsupportedRoute
            }
            return try Self.success(snapshot)
        } catch let error as ExecutionRemoteError { return Self.failure(error) }
        catch is CancellationError { return Self.failure(.timedOut) }
        catch { return Self.failure(.rejected) }
    }

    public static func failure(_ error: ExecutionRemoteError) -> ServiceHTTPResponse {
        let status: Int
        switch error {
        case .unauthorized: status = 401
        case .unsupportedRoute: status = 404
        case .oversizedRequest: status = 413
        case .malformedRequest, .invalidConfiguration: status = 400
        case .timedOut: status = 408
        case .oversizedResponse, .invalidResponse, .unavailable: status = 503
        case .rejected: status = 409
        }
        // A fixed message excludes host paths, subprocess output, headers and upstream account credentials.
        let data = Data("{\"error\":\"executor_request_failed\"}".utf8)
        return ServiceHTTPResponse(data: data, statusCode: status)
    }

    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do { return try JSONDecoder().decode(Value.self, from: data) }
        catch { throw ExecutionRemoteError.malformedRequest }
    }

    private static func success<Value: Encodable>(_ value: Value) throws -> ServiceHTTPResponse {
        let data = try JSONEncoder().encode(value)
        guard data.count <= ExecutionRemoteLimits.maximumResponseBytes else { throw ExecutionRemoteError.oversizedResponse }
        return ServiceHTTPResponse(data: data, statusCode: 200)
    }
}

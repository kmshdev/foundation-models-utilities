import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ServiceClientError: Error, Sendable, Equatable, LocalizedError {
    case invalidInput(String)
    case missingCredential
    case http(status: Int, retryAfter: String?)
    case invalidResponse
    case graphQL
    case mutationRejected
    case scopeMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let field): "Invalid \(field)."
        case .missingCredential: "Connect an account before using this service."
        case .http(let status, let retryAfter):
            "Service returned HTTP \(status)." + (retryAfter.map { " Retry after \($0)." } ?? "")
        case .invalidResponse: "The service returned an unreadable response."
        case .graphQL: "Linear returned query errors. No partial result was accepted."
        case .mutationRejected: "The service did not confirm that the change was saved."
        case .scopeMismatch: "The service response does not match the configured scope."
        }
    }
}

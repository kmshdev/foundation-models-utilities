import Foundation

public enum ExecutionRemoteError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration
    case malformedRequest
    case oversizedRequest
    case unauthorized
    case unsupportedRoute
    case rejected
    case unavailable
    case invalidResponse
    case oversizedResponse
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Use an HTTPS executor address and valid pairing credentials."
        case .malformedRequest: "The executor request was malformed."
        case .oversizedRequest: "The executor request exceeded its size limit."
        case .unauthorized: "The executor or Cloudflare Access did not accept these credentials."
        case .unsupportedRoute: "The executor does not support this request."
        case .rejected: "The executor rejected this operation. Refresh its state before trying again."
        case .unavailable: "The executor could not be reached. Refresh its state to check whether the operation arrived."
        case .invalidResponse: "The executor returned an unreadable response."
        case .oversizedResponse: "The executor response exceeded its size limit."
        case .timedOut: "The executor request timed out. Refresh its state before retrying an operation."
        }
    }
}

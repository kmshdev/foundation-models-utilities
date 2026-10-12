import Foundation

/// Errors omit raw provider bodies, prompts and credentials.
public enum ChatGPTResponsesError: Error, Sendable, Equatable, LocalizedError {
    case invalidRequest(String)
    case invalidResponse
    case invalidStream
    case oversizedEvent
    case interrupted
    case http(status: Int, code: String?, retryAfter: String?)
    case failed(code: String?)
    case incomplete(reason: String?)
    case usageLimit
    case usageUnavailable
    case refusal
    case unsupportedSchema

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let field): "Invalid ChatGPT request: \(field)."
        case .invalidResponse: "ChatGPT returned an unreadable response."
        case .invalidStream: "ChatGPT returned an invalid stream event."
        case .oversizedEvent: "A ChatGPT stream event exceeded the supported size."
        case .interrupted: "ChatGPT stopped before confirming that the response completed."
        case .http(let status, _, _): "ChatGPT returned HTTP \(status)."
        case .failed: "ChatGPT could not complete the response."
        case .incomplete: "ChatGPT returned an incomplete response."
        case .usageLimit: "Your shared ChatGPT plan usage limit has been reached."
        case .usageUnavailable: "ChatGPT plan usage is temporarily unavailable."
        case .refusal: "The model declined this request."
        case .unsupportedSchema: "This generation schema is not supported by ChatGPT structured output."
        }
    }

    package static func providerFailure(code: String?, status: Int? = nil, retryAfter: String? = nil) -> Self {
        let safe = safeCode(code)
        switch safe {
        case "subscription_sharing_usage_limit_exceeded": return .usageLimit
        case "subscription_sharing_usage_unavailable": return .usageUnavailable
        default:
            if let status { return .http(status: status, code: safe, retryAfter: safeCode(retryAfter)) }
            return .failed(code: safe)
        }
    }

    package static func safeCode(_ value: String?) -> String? {
        guard let value, value.count <= 128,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.: ".contains($0)) }) else { return nil }
        return value
    }
}

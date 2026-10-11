import EngineeringCore
import Foundation
import FoundationModels

enum ChatGPTLanguageModelErrorMapper {
    static func map(_ error: ChatGPTResponsesError) -> any Error {
        switch error {
        case .http(status: 429, _, let retryAfter):
            let reset = retryAfter.flatMap(TimeInterval.init).map { Date().addingTimeInterval($0) }
            return LanguageModelError.rateLimited(.init(resetDate: reset, debugDescription: "ChatGPT returned HTTP 429."))
        case .refusal:
            return LanguageModelError.refusal(.init(explanation: "The model declined this request.",
                                                    debugDescription: "ChatGPT emitted a refusal."))
        case .incomplete(reason: "content_filter"):
            return LanguageModelError.guardrailViolation(.init(debugDescription: "ChatGPT filtered the response."))
        case .unsupportedSchema, .http(_, code: "invalid_json_schema", _), .failed(code: "invalid_json_schema"):
            return LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil,
                                                                       debugDescription: "ChatGPT rejected the generation schema."))
        default: return error
        }
    }
}

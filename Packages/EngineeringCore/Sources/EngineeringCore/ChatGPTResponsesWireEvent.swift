import Foundation

struct ChatGPTResponsesWireEvent: Decodable {
    let type: String
    let delta: String?
    let code: String?
    let error: Failure?
    let response: Response?

    struct Failure: Decodable { let code: String? }
    struct Response: Decodable {
        let status: String?
        let error: Failure?
        let incompleteDetails: Incomplete?
        let usage: Usage?
        let output: [Output]?
        enum CodingKeys: String, CodingKey { case status, error, usage, output, incompleteDetails = "incomplete_details" }
    }
    struct Incomplete: Decodable { let reason: String? }
    struct Output: Decodable {
        let type: String
        let content: [Content]?
    }
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let inputTokensDetails: InputDetails?
        let outputTokensDetails: OutputDetails?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens", outputTokens = "output_tokens"
            case inputTokensDetails = "input_tokens_details", outputTokensDetails = "output_tokens_details"
        }
        struct InputDetails: Decodable {
            let cachedTokens: Int?
            enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
        }
        struct OutputDetails: Decodable {
            let reasoningTokens: Int?
            enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
        }

        func validated() throws -> ChatGPTResponsesUsage {
            let cached = inputTokensDetails?.cachedTokens ?? 0
            let reasoning = outputTokensDetails?.reasoningTokens ?? 0
            guard inputTokens >= 0, outputTokens >= 0, cached >= 0, cached <= inputTokens,
                  reasoning >= 0, reasoning <= outputTokens else { throw ChatGPTResponsesError.invalidStream }
            return .init(inputTokens: inputTokens, cachedInputTokens: cached,
                         outputTokens: outputTokens, reasoningOutputTokens: reasoning)
        }
    }
}

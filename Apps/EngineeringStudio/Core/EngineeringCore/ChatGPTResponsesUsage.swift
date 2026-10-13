import Foundation

/// Authoritative cumulative usage reported with a completed response.
public struct ChatGPTResponsesUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, reasoningOutputTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}

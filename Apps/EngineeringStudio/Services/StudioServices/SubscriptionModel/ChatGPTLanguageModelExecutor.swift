import EngineeringServices
import EngineeringCore
import Foundation
import FoundationModels

package struct ChatGPTLanguageModelExecutor: LanguageModelExecutor {
    package typealias Model = ChatGPTLanguageModel

    package struct Configuration: Hashable, Sendable {
        let modelName: String
        /// Identifies the immutable client/provider context without embedding any credential.
        let configurationID: UUID
    }

    private let configuration: Configuration
    package init(configuration: Configuration) { self.configuration = configuration }

    package func respond(to request: LanguageModelExecutorGenerationRequest, model: Model,
                 streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        // These controls are explicitly unsupported on the subscription route.
        guard request.generationOptions.temperature == nil,
              request.generationOptions.samplingMode == nil,
              request.generationOptions.maximumResponseTokens == nil else {
            throw ChatGPTResponsesError.invalidRequest("sampling and response-token controls are unavailable on this route")
        }
        guard request.enabledToolDefinitions.isEmpty else {
            throw LanguageModelError.unsupportedCapability(.init(capability: .toolCalling,
                                                                  debugDescription: "This subscription adapter has no tool executor."))
        }
        let format: ChatGPTResponsesFormat?
        if let schema = request.schema {
            guard model.supportsGuidedGeneration else {
                throw LanguageModelError.unsupportedCapability(.init(capability: .guidedGeneration,
                                                                      debugDescription: "Guided generation was disabled for this model."))
            }
            do {
                format = try ChatGPTResponsesFormat(name: schema.name, schemaJSON: JSONEncoder().encode(schema))
            } catch {
                throw LanguageModelError.unsupportedGenerationGuide(.init(schemaName: schema.name,
                                                                          debugDescription: "Schema cannot be represented by strict Responses structured output."))
            }
        } else { format = nil }
        let input = try ChatGPTTranscriptConverter.messages(from: request.transcript)
        let providerRequest = ChatGPTResponsesRequest(model: configuration.modelName, input: input, format: format)
        let entryID = UUID().uuidString
        do {
            for try await event in model.client.response(to: providerRequest) {
                try Task.checkCancellation()
                switch event {
                case .textDelta(let text):
                    await channel.send(.response(entryID: entryID, action: .appendText(text, tokenCount: 0)))
                case .completed(let usage):
                    if let usage {
                        await channel.send(.response(entryID: entryID, action: .updateUsage(
                            input: .init(totalTokenCount: usage.inputTokens, cachedTokenCount: usage.cachedInputTokens),
                            output: .init(totalTokenCount: usage.outputTokens, reasoningTokenCount: usage.reasoningOutputTokens)
                        )))
                    }
                }
            }
        } catch let error as ChatGPTResponsesError {
            throw ChatGPTLanguageModelErrorMapper.map(error)
        } catch let error as URLError where error.code == .timedOut {
            throw LanguageModelError.timeout(.init(debugDescription: "ChatGPT inference timed out."))
        }
    }
}

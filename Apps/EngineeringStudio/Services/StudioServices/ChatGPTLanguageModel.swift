import EngineeringServices
import EngineeringCore
import Foundation
import FoundationModels

/// A personal ChatGPT subscription model used through Apple's native session API.
/// Tools, attachments and provider reasoning are deliberately not advertised by this text adapter.
package struct ChatGPTLanguageModel: LanguageModel {
    package typealias Executor = ChatGPTLanguageModelExecutor

    package let name: String
    package let client: ChatGPTResponsesClient
    package let supportsGuidedGeneration: Bool
    private let configurationID: UUID

    package init(name: String, client: ChatGPTResponsesClient, supportsGuidedGeneration: Bool = true) {
        self.name = name
        self.client = client
        self.supportsGuidedGeneration = supportsGuidedGeneration
        configurationID = UUID()
    }

    package var capabilities: LanguageModelCapabilities {
        supportsGuidedGeneration ? LanguageModelCapabilities([.guidedGeneration]) : LanguageModelCapabilities([])
    }

    package var executorConfiguration: Executor.Configuration {
        .init(modelName: name, configurationID: configurationID)
    }
}

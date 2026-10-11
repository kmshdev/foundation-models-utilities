import EngineeringCore
import Foundation
import FoundationModels

/// A personal ChatGPT subscription model used through Apple's native session API.
/// Tools, attachments and provider reasoning are deliberately not advertised by this text adapter.
struct ChatGPTLanguageModel: LanguageModel {
    typealias Executor = ChatGPTLanguageModelExecutor

    let name: String
    let client: ChatGPTResponsesClient
    let supportsGuidedGeneration: Bool
    private let configurationID: UUID

    init(name: String, client: ChatGPTResponsesClient, supportsGuidedGeneration: Bool = true) {
        self.name = name
        self.client = client
        self.supportsGuidedGeneration = supportsGuidedGeneration
        configurationID = UUID()
    }

    var capabilities: LanguageModelCapabilities {
        supportsGuidedGeneration ? LanguageModelCapabilities([.guidedGeneration]) : LanguageModelCapabilities([])
    }

    var executorConfiguration: Executor.Configuration {
        .init(modelName: name, configurationID: configurationID)
    }
}

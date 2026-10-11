import Foundation

/// The deliberately small, documented ChatGPT plan-usage request contract.
public struct ChatGPTResponsesRequest: Encodable, Sendable {
    public let model: String
    public let input: [ChatGPTResponsesMessage]
    public let format: ChatGPTResponsesFormat?

    public init(model: String, input: [ChatGPTResponsesMessage], format: ChatGPTResponsesFormat? = nil) {
        self.model = model
        self.input = input
        self.format = format
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        try container.encode(false, forKey: .store)
        try container.encode(true, forKey: .stream)
        if let format {
            var text = container.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
            try text.encode(format, forKey: .format)
        }
    }

    func validate() throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count <= 256 else {
            throw ChatGPTResponsesError.invalidRequest("model")
        }
        guard !input.isEmpty, input.contains(where: { $0.role == .user && !$0.content.isEmpty }) else {
            throw ChatGPTResponsesError.invalidRequest("conversation")
        }
    }

    private enum CodingKeys: String, CodingKey { case model, input, store, stream, text }
    private enum TextKeys: String, CodingKey { case format }
}

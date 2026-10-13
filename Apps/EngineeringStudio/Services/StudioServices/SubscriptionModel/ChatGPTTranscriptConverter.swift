import EngineeringServices
import EngineeringCore
import FoundationModels

package enum ChatGPTTranscriptConverter {
    package static func messages(from entries: some Collection<Transcript.Entry>) throws -> [ChatGPTResponsesMessage] {
        try entries.map { entry in
            switch entry {
            case .instructions(let instructions):
                return .init(role: .developer, content: try text(instructions.segments, entry: entry))
            case .prompt(let prompt):
                return .init(role: .user, content: try text(prompt.segments, entry: entry))
            case .response(let response):
                return .init(role: .assistant, content: try text(response.segments, entry: entry))
            default:
                throw LanguageModelError.unsupportedTranscriptContent(.init(
                    unsupportedContent: [entry], debugDescription: "The subscription text adapter cannot replay this transcript entry."
                ))
            }
        }
    }

    private static func text(_ segments: some Collection<Transcript.Segment>, entry: Transcript.Entry) throws -> String {
        try segments.map { segment in
            switch segment {
            case .text(let text): return text.content
            case .structure(let structure): return structure.content.jsonString
            default:
                throw LanguageModelError.unsupportedTranscriptContent(.init(
                    unsupportedContent: [entry], debugDescription: "The subscription text adapter does not accept attachments."
                ))
            }
        }.joined(separator: "\n")
    }
}

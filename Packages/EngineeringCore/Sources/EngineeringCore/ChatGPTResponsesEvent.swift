/// Partial text is not a success receipt. Completion is a separate terminal event.
public enum ChatGPTResponsesEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(ChatGPTResponsesUsage?)
}

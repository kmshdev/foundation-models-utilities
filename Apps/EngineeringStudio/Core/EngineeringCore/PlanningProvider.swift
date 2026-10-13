package enum PlanningProvider: String, CaseIterable, Identifiable {
    case disabled, onDevice, chatGPT

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .disabled: "Off"
        case .onDevice: "Apple Intelligence"
        case .chatGPT: "ChatGPT subscription"
        }
    }
}

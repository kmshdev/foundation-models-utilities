enum PlanningProvider: String, CaseIterable, Identifiable {
    case disabled, onDevice, chatGPT

    var id: String { rawValue }
    var title: String {
        switch self {
        case .disabled: "Off"
        case .onDevice: "Apple Intelligence"
        case .chatGPT: "ChatGPT subscription"
        }
    }
}

package enum ProviderMCPPhase: Equatable, Sendable {
    case disconnected, restoring, restored, configurationRequired
    case authorizing, connecting, refreshing, configuring, ready
    case authorizationRequired, disconnecting, cancelling, failed

    package var isBusy: Bool {
        switch self {
        case .restoring, .authorizing, .connecting, .refreshing, .configuring, .disconnecting, .cancelling: true
        default: false
        }
    }
}

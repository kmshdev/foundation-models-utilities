import Foundation

enum ChatGPTConnectionError: LocalizedError {
    case notConnected, noModelSelected, modelAccessUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected: "Sign in with ChatGPT in Settings to use your subscription."
        case .noModelSelected: "Refresh the available ChatGPT models and choose a model in Settings."
        case .modelAccessUnavailable: "ChatGPT model access could not be verified. Refresh models or sign in again in Settings."
        }
    }
}

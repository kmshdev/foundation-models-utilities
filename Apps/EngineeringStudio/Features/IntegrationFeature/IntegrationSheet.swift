import Foundation

enum IntegrationSheet: Identifiable {
    case githubApplication(connectAfterSave: Bool)

    var id: String {
        switch self {
        case .githubApplication(let connectAfterSave):
            connectAfterSave ? "github-connect" : "github-registration"
        }
    }
}

import EngineeringMCP
import Foundation

actor ProviderOAuthFixtureBrowser: ProviderOAuthBrowser {
    enum Mode: Sendable { case success, duplicateState, valuelessIssuer, emptyIssuer, wrongIssuer, denied }
    let mode: Mode
    private var prepared = 0
    private var canceled: [UUID] = []
    private(set) var authorizationURL: URL?

    init(mode: Mode = .success) { self.mode = mode }

    func prepareCallback(for provider: MCPProvider) async throws -> ProviderOAuthBrowserAttempt {
        prepared += 1
        return .init(redirectURI: provider == .github ? URL(string: "engineeringstudio://oauth/github")!
                     : URL(string: "http://127.0.0.1:\(12_300 + prepared)/oauth/linear/callback")!)
    }

    func present(authorizationURL: URL, attempt: ProviderOAuthBrowserAttempt) async throws -> URL {
        self.authorizationURL = authorizationURL
        let state = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
            .first { $0.name == "state" }!.value!
        var value = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
        value.queryItems = [.init(name: "state", value: state), .init(name: "code", value: "fixture-code")]
        switch mode {
        case .success: break
        case .duplicateState: value.queryItems!.append(.init(name: "state", value: state))
        case .valuelessIssuer: value.queryItems!.append(.init(name: "iss", value: nil))
        case .emptyIssuer: value.queryItems!.append(.init(name: "iss", value: ""))
        case .wrongIssuer: value.queryItems!.append(.init(name: "iss", value: "https://example.invalid"))
        case .denied: throw ProviderOAuthError.authorizationDenied
        }
        return value.url!
    }

    func cancel(attemptID: UUID) async { canceled.append(attemptID) }
}

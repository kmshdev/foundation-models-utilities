import EngineeringMCP
import Foundation

/// A local browser fixture, not evidence of provider consent or a real listener.
actor ProviderCheckBrowser: ProviderOAuthBrowser {
    let presentationGate = ProviderCheckGate()
    private(set) var preparationCount = 0
    private(set) var presentationCount = 0
    private(set) var cancellationCount = 0
    private(set) var requestedScopes: [String] = []

    var counts: (prepared: Int, presented: Int, canceled: Int) {
        (preparationCount, presentationCount, cancellationCount)
    }

    func prepareCallback(for provider: MCPProvider) -> ProviderOAuthBrowserAttempt {
        preparationCount += 1
        let callback = provider == .github ? "engineeringstudio://oauth/github"
            : "http://127.0.0.1:48632/oauth/linear/callback"
        return .init(redirectURI: URL(string: callback)!)
    }

    func present(authorizationURL: URL, attempt: ProviderOAuthBrowserAttempt) async throws -> URL {
        presentationCount += 1
        let query = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let state = query.first(where: { $0.name == "state" })?.value,
              query.first(where: { $0.name == "code_challenge_method" })?.value == "S256",
              query.first(where: { $0.name == "redirect_uri" })?.value == attempt.redirectURI.absoluteString,
              let challenge = query.first(where: { $0.name == "code_challenge" })?.value,
              challenge.count == 43 else {
            throw ProviderCheckFailure.assertion("OAuth browser request must bind PKCE, state and the allocated callback")
        }
        requestedScopes.append(query.first(where: { $0.name == "scope" })?.value ?? "")
        await presentationGate.waitIfSuspended()
        var callback = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
        callback.queryItems = [.init(name: "code", value: "isolated-fixture-code"), .init(name: "state", value: state)]
        return callback.url!
    }

    func cancel(attemptID: UUID) { cancellationCount += 1 }
}

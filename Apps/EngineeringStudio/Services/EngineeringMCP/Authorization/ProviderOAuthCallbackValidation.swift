import Foundation
import MCP

public enum ProviderOAuthCallbackValidation {
    /// Check duplicate parameters and the full registered callback before the SDK extracts the code.
    public static func code(from callback: URL, redirectURI: URL, state: String, issuer: URL) throws -> String {
        guard callback.absoluteString.utf8.count <= 16_384,
              let actual = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == expected.scheme?.lowercased(),
              actual.host?.lowercased() == expected.host?.lowercased(), actual.port == expected.port,
              actual.percentEncodedPath == expected.percentEncodedPath,
              actual.user == nil, actual.password == nil, actual.fragment == nil else {
            throw ProviderOAuthError.invalidCallback
        }
        let items = actual.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state else {
            throw ProviderOAuthError.invalidCallback
        }
        if let returnedIssuer = items.first(where: { $0.name == "iss" }) {
            guard let value = returnedIssuer.value, !value.isEmpty, value == issuer.absoluteString else {
                throw ProviderOAuthError.invalidCallback
            }
        }
        if items.contains(where: { $0.name == "error" }) { throw ProviderOAuthError.authorizationDenied }
        do {
            return try OAuthAuthorizationCodeFlow().extractCode(from: callback,
                                                                expectedRedirectURI: redirectURI,
                                                                expectedState: state)
        } catch { throw ProviderOAuthError.invalidCallback }
    }
}

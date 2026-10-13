import AuthenticationServices
import EngineeringMCP
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// System browser login; credentials and passkeys are entered only on the provider’s own page.
@MainActor
package final class ProviderOAuthNativeBrowser: NSObject, ProviderOAuthBrowser, ASWebAuthenticationPresentationContextProviding {
    private let provider: MCPProvider
    private let timeoutDuration: Duration
    private var attempt: ProviderOAuthBrowserAttempt?
    private var preparingID: UUID?
    private var listener: ProviderOAuthLoopbackListener?
    private var browser: ASWebAuthenticationSession?
    private var callback: CheckedContinuation<URL, any Error>?
    private var anchor: ASPresentationAnchor?
    private var timeout: Task<Void, Never>?

    package init(provider: MCPProvider, timeout: Duration = .seconds(300)) {
        self.provider = provider
        timeoutDuration = timeout
    }

    package func prepareCallback(for provider: MCPProvider) async throws -> ProviderOAuthBrowserAttempt {
        guard provider == self.provider else { throw ProviderOAuthError.invalidCallback }
        guard preparingID == nil else { throw ProviderOAuthError.authorizationInProgress }
        let id = UUID(); preparingID = id
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let redirect: URL
                if provider == .github {
                    redirect = URL(string: "engineeringstudio://oauth/github")!
                } else {
                    let listener = ProviderOAuthLoopbackListener()
                    self.listener = listener
                    let port = try await listener.start()
                    guard preparingID == id else { throw ProviderOAuthError.canceled }
                    redirect = URL(string: "http://127.0.0.1:\(port)\(ProviderOAuthLoopbackRequest.path)")!
                }
                try Task.checkCancellation()
                let value = ProviderOAuthBrowserAttempt(id: id, redirectURI: redirect)
                attempt = value
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: self?.timeoutDuration ?? .seconds(300)) }
                    catch { return }
                    self?.cleanup(id: id, result: .failure(ProviderOAuthError.authorizationExpired))
                }
                return value
            } catch {
                cleanup(id: id, result: .failure(ProviderOAuthError.canceled))
                throw error
            }
        } onCancel: { [weak self] in Task { @MainActor in await self?.cancel(attemptID: id) } }
    }

    package func present(authorizationURL: URL, attempt: ProviderOAuthBrowserAttempt) async throws -> URL {
        guard self.attempt == attempt, preparingID == attempt.id,
              let components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.fragment == nil,
              components.host == (provider == .github ? "github.com" : "mcp.linear.app"),
              components.path == (provider == .github ? "/login/oauth/authorize" : "/authorize"),
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              !state.isEmpty else { throw ProviderOAuthError.invalidCallback }
        let id = attempt.id
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                if provider == .linear {
                    guard let listener else { throw ProviderOAuthError.canceled }
                    listener.configure(state: state)
                    #if os(macOS)
                    guard NSWorkspace.shared.open(authorizationURL) else { throw ProviderOAuthError.presentationUnavailable }
                    #else
                    try validateAnchor()
                    // Apple's modern Callback API supports custom schemes and associated HTTPS,
                    // not HTTP loopback. NWListener owns this documented native redirect instead.
                    let browser = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: nil) { [weak self] _, error in
                        guard error != nil else { return }
                        Task { @MainActor in
                            guard let self, self.preparingID == id, self.browser != nil else { return }
                            await self.cancel(attemptID: id)
                        }
                    }
                    browser.presentationContextProvider = self
                    self.browser = browser
                    guard browser.start() else { throw ProviderOAuthError.presentationUnavailable }
                    #endif
                    let value = try await listener.waitForCallback()
                    guard preparingID == id else { throw ProviderOAuthError.canceled }
                    cleanup(id: id, result: .success(value))
                    return value
                }
                try validateAnchor()
                return try await withCheckedThrowingContinuation { continuation in
                    callback = continuation
                    let browser = ASWebAuthenticationSession(url: authorizationURL,
                                                            callback: .customScheme("engineeringstudio")) { [weak self] url, error in
                        Task { @MainActor in
                            guard let self, self.preparingID == id else { return }
                            if error != nil || url == nil {
                                self.cleanup(id: id, result: .failure(ProviderOAuthError.canceled))
                            } else if let url {
                                self.cleanup(id: id, result: .success(url))
                            }
                        }
                    }
                    browser.presentationContextProvider = self
                    self.browser = browser
                    if !browser.start() { cleanup(id: id, result: .failure(ProviderOAuthError.presentationUnavailable)) }
                }
            } catch {
                cleanup(id: id, result: .failure(ProviderOAuthError.canceled))
                throw error
            }
        } onCancel: { [weak self] in Task { @MainActor in await self?.cancel(attemptID: id) } }
    }

    package func cancel(attemptID: UUID) async {
        cleanup(id: attemptID, result: .failure(ProviderOAuthError.canceled))
    }

    private func validateAnchor() throws {
        #if os(macOS)
        anchor = NSApp.keyWindow ?? NSApp.mainWindow
        #else
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
        #endif
        guard anchor != nil else { throw ProviderOAuthError.presentationUnavailable }
    }

    private func cleanup(id: UUID, result: Result<URL, any Error>) {
        guard preparingID == id else { return }
        preparingID = nil; attempt = nil
        timeout?.cancel(); timeout = nil
        let callback = self.callback; self.callback = nil
        let browser = self.browser; self.browser = nil
        browser?.cancel()
        listener?.cancel(); listener = nil; anchor = nil
        callback?.resume(with: result)
    }

    package func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let anchor else { preconditionFailure("The authentication browser requires a validated app window.") }
        return anchor
    }
}

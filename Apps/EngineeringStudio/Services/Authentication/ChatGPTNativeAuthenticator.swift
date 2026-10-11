import Foundation
import AuthenticationServices
import EngineeringCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class ChatGPTNativeAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let session: ChatGPTSession
    private var listener: ChatGPTLoopbackListener?
    private var browser: ASWebAuthenticationSession?
    private var attemptID: UUID?
    #if !os(macOS)
    private var anchor: UIWindow?
    #endif

    init(session: ChatGPTSession) { self.session = session }

    func signIn(accountID: String? = nil, enablePlanUsage: Bool = false) async throws -> ChatGPTAccount {
        guard attemptID == nil else { throw ChatGPTAuthenticationError.authorizationInProgress }
        let id = UUID(); attemptID = id
        let listener = ChatGPTLoopbackListener(); self.listener = listener
        return try await withTaskCancellationHandler {
            defer { if attemptID == id { cleanup() } }
            do {
                let port = try await listener.start()
                try Task.checkCancellation()
                let attempt = try await session.beginAuthorization(port: port, accountID: accountID, enablePlanUsage: enablePlanUsage)
                listener.configure(attempt)
                #if os(macOS)
                guard NSWorkspace.shared.open(attempt.authorizationURL) else { throw ChatGPTAuthenticationError.canceled }
                #else
                anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
                guard anchor != nil else { throw ChatGPTAuthenticationError.canceled }
                // HTTP loopback is received by NWListener. It is NOT an AS session callback scheme.
                // The optional nil scheme keeps this system browser open until listener completion/cancel.
                let browser = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: nil) { [weak self] _, error in
                    guard error != nil else { return }
                    Task { @MainActor in
                        guard let self, self.attemptID == id, self.browser != nil else { return }
                        self.cancel()
                    }
                }
                browser.presentationContextProvider = self
                self.browser = browser
                guard browser.start() else { throw ChatGPTAuthenticationError.canceled }
                #endif
                let callback = try await listener.waitForCallback()
                try Task.checkCancellation()
                guard attemptID == id else { throw ChatGPTAuthenticationError.canceled }
                // Close the browser after the loopback callback; avoid treating our cancel as user cancellation.
                let browser = self.browser; self.browser = nil; browser?.cancel()
                return try await session.completeAuthorization(callbackURL: callback)
            } catch {
                await session.cancelAuthorization()
                throw error
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
    }

    func cancel() {
        cleanup(endingAttempt: false)
        Task { await session.cancelAuthorization() }
    }

    private func cleanup(endingAttempt: Bool = true) {
        if endingAttempt { attemptID = nil }
        listener?.cancel(); listener = nil
        let browser = self.browser; self.browser = nil; browser?.cancel()
        #if !os(macOS)
        anchor = nil
        #endif
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()
        #else
        anchor ?? UIWindow()
        #endif
    }
}

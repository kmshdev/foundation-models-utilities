import EngineeringCore
import Foundation
import Observation

@MainActor @Observable
final class ChatGPTConnection {
    private(set) var accounts: [ChatGPTAccount] = []
    private(set) var activeAccount: ChatGPTAccount?
    private(set) var models: [ChatGPTModelChoice] = []
    private(set) var selectedModel: String?
    private(set) var catalogState: ChatGPTCatalogState = .notLoaded
    private(set) var isSigningIn = false
    private(set) var isRefreshing = false
    private(set) var error: String?
    private(set) var signOutStatus: String?
    var isSignedIn: Bool { activeAccount?.isSignedIn == true && activeAccount?.planUsageEnabled == true }
    var isReadyForPlanning: Bool { isSignedIn && catalogState == .available && models.contains { $0.slug == selectedModel } }
    var status: String {
        if isSigningIn { return "Signing in…" }
        if isRefreshing { return "Loading models…" }
        if isReadyForPlanning { return "Connected" }
        if isSignedIn, catalogState == .failed { return "Model access unavailable" }
        if isSignedIn { return "Signed in · Choose a model" }
        if activeAccount?.isSignedIn == true { return "Subscription access not enabled" }
        return "Sign in required"
    }
    @ObservationIgnored let session: ChatGPTSession
    @ObservationIgnored let responsesClient: ChatGPTResponsesClient
    @ObservationIgnored private let authenticator: ChatGPTNativeAuthenticator
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var generation = UUID()

    /// Construction creates adapters only; credential reads begin with load().
    init(session: ChatGPTSession = ChatGPTAuthenticationFactory.makeSession(),
         client: ChatGPTResponsesClient? = nil) {
        self.session = session
        responsesClient = client ?? ChatGPTResponsesClient(tokenProvider: session)
        authenticator = ChatGPTNativeAuthenticator(session: session)
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        let expected = generation
        do {
            try await session.restore()
            guard generation == expected else { return }
            await updateAccounts()
            if isSignedIn { await refreshModels() }
        } catch {
            if generation == expected { self.error = error.localizedDescription; didLoad = false }
        }
    }

    func signIn(addAccount: Bool = false, enablePlanUsage: Bool = false) async {
        guard !isSigningIn, !isRefreshing else { return }
        generation = UUID()
        let expected = generation
        isSigningIn = true; error = nil; signOutStatus = nil
        defer { if generation == expected { isSigningIn = false } }
        do {
            _ = try await authenticator.signIn(accountID: addAccount ? nil : activeAccount?.id,
                                              enablePlanUsage: enablePlanUsage)
            guard generation == expected else { return }
            await updateAccounts()
            await refreshModels()
        } catch is CancellationError { }
        catch { if generation == expected { self.error = error.localizedDescription } }
    }

    func cancelSignIn() {
        generation = UUID()
        authenticator.cancel()
        isSigningIn = false
        isRefreshing = false
    }

    func selectAccount(_ id: String) async {
        guard !isSigningIn, !isRefreshing, id != activeAccount?.id else { return }
        generation = UUID()
        let expected = generation
        do {
            try await session.selectAccount(id: id)
            guard generation == expected else { return }
            models = []; selectedModel = nil; catalogState = .notLoaded; error = nil; signOutStatus = nil
            await updateAccounts()
            if isSignedIn { await refreshModels() }
        } catch { if generation == expected { self.error = error.localizedDescription } }
    }

    func refreshModels() async {
        guard !isRefreshing, isSignedIn else { return }
        isRefreshing = true
        catalogState = .loading
        let expected = generation
        defer { if generation == expected { isRefreshing = false } }
        do {
            let choices = try await responsesClient.models()
            guard generation == expected else { return }
            models = choices
            catalogState = .available
            let saved = activeAccount.map { UserDefaults.standard.string(forKey: modelPreferenceKey($0.id)) } ?? nil
            let preferred = selectedModel ?? saved
            selectedModel = choices.first(where: { $0.slug == preferred })?.slug ?? choices.first?.slug
            error = choices.isEmpty ? "This account has no available subscription models." : nil
            saveModelPreference()
        } catch {
            if generation == expected {
                self.error = error.localizedDescription
                catalogState = .failed
                await updateAccounts()
            }
        }
    }

    func selectModel(_ slug: String?) {
        guard let slug, models.contains(where: { $0.slug == slug }) else { return }
        selectedModel = slug
        saveModelPreference()
    }

    func signOut() async {
        cancelSignIn()
        isRefreshing = false
        let expected = generation
        do {
            let revoked = try await session.signOut()
            guard generation == expected else { return }
            models = []; selectedModel = nil; catalogState = .notLoaded; error = nil
            await updateAccounts()
            signOutStatus = revoked ? "Signed out" : "Signed out on this device. Remote revocation could not be confirmed."
        } catch {
            if generation == expected {
                models = []; selectedModel = nil; catalogState = .notLoaded
                await updateAccounts()
                self.error = error.localizedDescription
            }
        }
    }

    func requireSelectedModel() throws -> String {
        guard isSignedIn else { throw ChatGPTConnectionError.notConnected }
        guard catalogState == .available else { throw ChatGPTConnectionError.modelAccessUnavailable }
        guard let selectedModel, models.contains(where: { $0.slug == selectedModel }) else {
            throw ChatGPTConnectionError.noModelSelected
        }
        return selectedModel
    }

    private func updateAccounts() async {
        let expected = generation
        let newAccounts = await session.accounts()
        let newActiveAccount = await session.activeAccount()
        guard generation == expected else { return }
        if newActiveAccount?.id != activeAccount?.id || newActiveAccount?.isSignedIn != true {
            models = []; selectedModel = nil
            catalogState = .notLoaded
        }
        accounts = newAccounts
        activeAccount = newActiveAccount
    }

    private func modelPreferenceKey(_ id: String) -> String { "chatgpt.selectedModel.\(id)" }
    private func saveModelPreference() {
        guard let account = activeAccount else { return }
        UserDefaults.standard.set(selectedModel, forKey: modelPreferenceKey(account.id))
    }
}

@testable import StudioWorkflows
@testable import StudioServices
import EngineeringServices
import EngineeringCore
import Foundation

/// Exercises composed startup and recovery with memory credentials and local fixtures.
@MainActor
func checkStudioStartup() async throws {
    let directory = URL.temporaryDirectory.appendingPathComponent("startup-check-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workspaceURL = directory.appendingPathComponent("workspace.json")
    try Data("invalid JSON".utf8).write(to: workspaceURL)

    let store = StudioStore(repository: WorkspaceRepository(url: workspaceURL))
    let credentials = StartupMemoryCredentials()
    let transport = StartupHTTPTransport()
    let vault = StartupCredentialVault()
    let session = ChatGPTSession(vault: vault, transport: transport,
                                signatureVerifier: StartupSignatureVerifier(),
                                authorizationCryptography: StartupCryptography())
    let account = ChatGPTConnection(session: session,
                                   client: ChatGPTResponsesClient(tokenProvider: session, catalogTransport: transport))
    let connections = ServiceConnections(credentialStore: credentials, transport: transport,
                                         githubMCP: fixtureProviderConnection(provider: .github),
                                         linearMCP: fixtureProviderConnection(provider: .linear))
    let runtime = DeveloperRuntimeConnection(credentials: credentials, remoteTransport: transport,
        receiptJournal: ExecutionReceiptJournal(url: directory.appendingPathComponent("receipts.json")))
    let dependencies = StudioDependencies(store: store, connections: connections, chatGPT: account, runtime: runtime)

    let first = Task { @MainActor in await dependencies.start() }
    do {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !(await vault.isWaiting) {
            guard clock.now < deadline else { throw startupFailure("Initial startup never reached the fixture gate") }
            try await Task.sleep(for: .milliseconds(5))
        }
        let second = Task { @MainActor in await dependencies.start() }
        await Task.yield()
        try startupRequire(!store.isLoaded, "Failed restoration never replaces the unreadable workspace")
        await vault.release()
        await first.value
        await second.value
    } catch {
        await vault.release()
        await first.value
        throw error
    }

    try startupRequire(!store.isLoaded && store.failure != nil,
                       "The completed initial startup retains its workspace-load failure")
    let initialVaultReads = await vault.loadCount
    let initialRequests = await transport.requestCount
    let initialCredentialReads = credentials.readCount
    try startupRequire(initialVaultReads == 1 && initialRequests == 3 && initialCredentialReads == 2,
                       "Concurrent initial scenes share one account and service startup")
    try startupRequire(!account.isSignedIn && !runtime.hasRuntime,
                       "Fixtures do not authenticate a real account or activate developer execution")

    var repaired = Workspace()
    let outcomeID = try repaired.recordOutcome("Recovered outcome")
    try JSONEncoder().encode(repaired).write(to: workspaceURL, options: .atomic)
    async let recoveredFirst: Void = dependencies.start()
    async let recoveredSecond: Void = dependencies.start()
    _ = await (recoveredFirst, recoveredSecond)
    try startupRequire(store.isLoaded && store.workspace == repaired && store.failure == nil,
                       "A later scene startup retries the repaired workspace")
    let retryVaultReads = await vault.loadCount
    let retryRequests = await transport.requestCount
    try startupRequire(retryVaultReads == initialVaultReads && retryRequests == initialRequests,
                       "Workspace retry preserves successful account and provider startup")

    let draft = store.draft(for: outcomeID)
    draft.text = "Unsent outcome context"
    store.newOutcomeDraft.text = "Unsent new outcome"
    try startupRequire(store.send("Retained conversation", to: outcomeID), "A recovered workspace accepts local edits")
    let pendingWorkspace = store.workspace
    await dependencies.start()
    await dependencies.start()
    try startupRequire(store.workspace == pendingWorkspace && store.draft(for: outcomeID) === draft &&
                       draft.text == "Unsent outcome context" && store.newOutcomeDraft.text == "Unsent new outcome",
                       "Opening more windows preserves workspace edits and owned draft instances")
    let finalVaultReads = await vault.loadCount
    let finalRequests = await transport.requestCount
    try startupRequire(finalVaultReads == initialVaultReads && finalRequests == initialRequests &&
                       credentials.readCount == initialCredentialReads,
                       "Successful repeated startup performs no additional credential or provider reads")
    try startupRequire(await dependencies.flush(), "The retained edits remain durably saveable")
    print("Studio startup checks passed: coalesced scenes, repaired-load recovery, preserved account/runtime startup and pending drafts.")
}

private func startupFailure(_ message: String) -> NSError {
    NSError(domain: "StartupChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private func startupRequire(_ condition: Bool, _ message: String) throws {
    guard condition else { throw startupFailure(message) }
}

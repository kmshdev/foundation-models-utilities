import EngineeringMCP
import EngineeringCore
import Foundation
@testable import StudioServices
@testable import StudioWorkflows

/// Safe dependency for existing native store/startup fixtures. Construction is
/// entirely in memory; it does not touch Keychain, a browser or external HTTP.
@MainActor
func fixtureProviderConnection(provider: MCPProvider) -> ProviderMCPConnection {
    do { return try ProviderCheckHarness(provider: provider, accountID: "fixture-\(UUID().uuidString)").connection }
    catch { preconditionFailure("The isolated provider fixture requires a nonempty identity") }
}

/// Exercises production actor and observable lifecycle with isolated adapters.
/// These checks establish native behavior, not live provider consent.
@MainActor
func checkProviderAuthorization() async throws {
    let cryptography = ProviderOAuthSDKCryptography()
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    try providerCheckRequire(try cryptography.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                             "Pinned SDK produces the RFC7636 S256 challenge with native CryptoKit")
    try await checkProviderNativeKeychain()
    try await checkProviderNativeLoopback()
    try await checkProviderStorageOnlyRestore()
    try await checkProviderSilentRefresh()
    try await checkProviderCancelledCallback()
    try await checkProviderCancelledStorageCommit()
    try await checkProviderDisconnectedExchange()
    try await checkProviderCancelledCapabilities()
    try await checkProviderStorageFailures()
    try await checkProviderLegacySeparation()
    print("Provider authorization checks passed: native S256, isolated Keychain, actual IPv4 loopback validation/cancellation/deadline, storage-only restore, saved-client refresh, browser and commit fences, MCP receipt ownership and protected-storage failures. All grants and MCP results are isolated fixtures.")
}

@MainActor
private func checkProviderStorageOnlyRestore() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    let initialStorage = await fixture.vault.counts
    let initialBrowser = await fixture.browser.counts
    let initialRequests = await fixture.http.requestCount
    try providerCheckRequire(initialStorage.reads == 0 && initialStorage.writes == 0,
                             "Constructing the provider lifecycle performs no protected-storage I/O")
    try providerCheckRequire(initialRequests == 0 && initialBrowser.presented == 0,
                             "Constructing the provider lifecycle never presents a browser or sends HTTP")
    try providerCheckRequire(fixture.connection.phase == .disconnected && fixture.connection.receipt == nil,
                             "A constructor cannot claim current MCP readiness")
    try await configureProviderCheckGitHub(fixture)
    await fixture.validator.validationGate.suspendNextOperation()
    let connecting = Task { @MainActor in await fixture.connection.connect() }
    do {
        try await waitForProviderCheckGate(fixture.validator.validationGate)
        try providerCheckRequire(fixture.connection.isBusy && fixture.connection.receipt == nil &&
                                 fixture.connection.phase == .connecting,
                                 "OAuth completion waits for MCP initialization/catalog before claiming readiness")
        await fixture.validator.validationGate.release()
        await connecting.value
    } catch {
        await fixture.validator.validationGate.release()
        await connecting.value
        throw error
    }
    try providerCheckRequire(fixture.connection.phase == .ready && fixture.connection.hasSavedAuthorization &&
                             fixture.connection.receipt?.identity == fixture.identity &&
                             fixture.connection.receipt?.serverName == "Isolated fixture MCP",
                             "A validated fixture MCP receipt establishes connection readiness")
    let requests = await fixture.http.requestCount
    let restarted = try ProviderCheckHarness(provider: .github, vault: fixture.vault, http: fixture.http)
    await restarted.connection.restore()
    try providerCheckRequire(restarted.connection.phase == .restored && restarted.connection.hasSavedAuthorization &&
                             restarted.connection.receipt == nil && restarted.connection.githubClientID == "isolated-github-client",
                             "Cold restore exposes saved metadata without claiming an initialized MCP connection")
    let restoredBrowser = await restarted.browser.counts
    let restoredRequests = await fixture.http.requestCount
    let restoredValidations = await restarted.validator.validationCount
    try providerCheckRequire(restoredBrowser.prepared == 0 && restoredBrowser.presented == 0 &&
                             restoredRequests == requests && restoredValidations == 0,
                             "Storage-only restoration never starts a browser, provider request or MCP handshake")
    await restarted.connection.refresh()
    let refreshedPresentations = await restarted.browser.presentationCount
    try providerCheckRequire(restarted.connection.phase == .ready && restarted.connection.receipt != nil &&
                             refreshedPresentations == 0,
                             "Explicit silent validation can verify a saved grant without opening the browser")
}

@MainActor
private func checkProviderSilentRefresh() async throws {
    let missing = try ProviderCheckHarness(provider: .linear)
    await missing.connection.refresh()
    let missingBrowser = await missing.browser.counts
    try providerCheckRequire(missing.connection.phase == .authorizationRequired && missing.connection.receipt == nil &&
                             missingBrowser.presented == 0 && missingBrowser.prepared == 0,
                             "Refresh with no grant requests sign-in without presenting account authentication")

    let first = try ProviderCheckHarness(provider: .linear)
    await first.http.setTokenLifetime(1)
    await first.connection.connect()
    try providerCheckRequire(first.connection.phase == .ready, "A read-only Linear DCR fixture completes initial authorization")
    let scopes = await first.browser.requestedScopes
    let initialRegistrations = await first.http.registrationCount
    try providerCheckRequire(scopes == ["read"] && initialRegistrations == 1,
                             "Linear explicitly requests read and registers its native client once")
    try await Task.sleep(for: .milliseconds(1_100))
    await first.http.setTokenLifetime(3_600)
    let restarted = try ProviderCheckHarness(provider: .linear, vault: first.vault, http: first.http)
    await restarted.connection.restore()
    await restarted.connection.refresh()
    let refreshBrowser = await restarted.browser.counts
    let refreshRequests = await first.http.snapshot
    try providerCheckRequire(restarted.connection.phase == .ready && restarted.connection.error == nil &&
                             refreshBrowser.presented == 0,
                             "A cold-restored expiring Linear grant refreshes silently")
    try providerCheckRequire(refreshRequests.grants == ["authorization_code", "refresh_token"] &&
                             refreshRequests.clientIDs == ["isolated-linear-client", "isolated-linear-client"] &&
                             refreshRequests.registrations == 1,
                             "Refresh retains the saved DCR client ID instead of registering a different client")
    // Disconnect does not authorize another account or widen a rejected scope.
    await restarted.connection.disconnect()
    await restarted.connection.refresh()
    let disconnectedPresentations = await restarted.browser.presentationCount
    try providerCheckRequire(restarted.connection.receipt == nil && restarted.connection.phase == .authorizationRequired &&
                             disconnectedPresentations == 0,
                             "Disconnected silent refresh cannot reopen the provider browser")

    let rejected = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(rejected)
    await rejected.http.setTokenLifetime(1)
    await rejected.connection.connect()
    let presentationsBeforeRejection = await rejected.browser.presentationCount
    await rejected.http.setRejectToken(true)
    await rejected.connection.refresh()
    let presentationsAfterRejection = await rejected.browser.presentationCount
    try providerCheckRequire(rejected.connection.phase == .authorizationRequired && rejected.connection.receipt == nil &&
                             rejected.connection.error != nil && presentationsBeforeRejection == presentationsAfterRejection,
                             "Rejected silent refresh clears MCP readiness and asks for explicit sign-in without opening a browser")
}

private func checkProviderNativeKeychain() async throws {
    let identity = try MCPConnectionIdentity(provider: .github, accountID: "isolated-native-keychain")
    let service = "dev.kmsh.engineeringstudio.provider-check.\(UUID().uuidString)"
    let vault = ProviderOAuthKeychainVault(service: service)
    let original = Data("isolated-configuration-data".utf8)
    let replacement = Data("isolated-replacement-data".utf8)
    do {
        try providerCheckRequire(try await vault.read(.configuration, for: identity) == nil,
                                 "An isolated native provider Keychain namespace starts empty")
        try await vault.write(original, record: .configuration, for: identity, transaction: .init())
        try providerCheckRequire(try await vault.read(.configuration, for: identity) == original,
                                 "Native protected provider record roundtrips")
        try await vault.write(replacement, record: .configuration, for: identity, transaction: .init())
        try providerCheckRequire(try await vault.read(.configuration, for: identity) == replacement,
                                 "Native protected provider record replaces atomically")
        let canceled = ProviderOAuthStorageTransaction()
        canceled.invalidate()
        do {
            try await vault.write(original, record: .configuration, for: identity, transaction: canceled)
            throw ProviderCheckFailure.assertion("Native Keychain must reject an invalidated transaction")
        } catch ProviderOAuthError.canceled { }
        try providerCheckRequire(try await vault.read(.configuration, for: identity) == replacement,
                                 "Canceled native storage mutation preserves the prior protected record")
        try await vault.write(nil, record: .configuration, for: identity, transaction: .init())
        try providerCheckRequire(try await vault.read(.configuration, for: identity) == nil,
                                 "Native fixture Keychain record is removed")
    } catch {
        try? await vault.write(nil, record: .configuration, for: identity, transaction: .init())
        throw error
    }
}

@MainActor
private func checkProviderNativeLoopback() async throws {
    let listener = ProviderOAuthLoopbackListener(timeout: .seconds(10))
    let port = try await listener.start()
    defer { listener.cancel() }
    let state = "isolated-loopback-state"
    listener.configure(state: state)
    let path = "/oauth/linear/callback"
    for (target, host) in [
        ("/wrong/path?code=fixture&state=\(state)", "127.0.0.1:\(port)"),
        ("\(path)?code=fixture&state=wrong", "127.0.0.1:\(port)"),
        ("\(path)?code=fixture&code=duplicate&state=\(state)", "127.0.0.1:\(port)"),
        ("\(path)?code=fixture&state=\(state)", "example.invalid:\(port)")
    ] {
        let request = "GET \(target) HTTP/1.1\r\nHost: \(host)\r\n\r\n"
        let response = try await ProviderCheckLoopbackExchange().send(request, port: port)
        try providerCheckRequire(response.hasPrefix("HTTP/1.1 400"),
                                 "Incorrect path/state/duplicate code/Host is rejected without consuming the native listener")
    }
    let request = "GET \(path)?code=fixture&state=\(state) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
    let waiting = Task { @MainActor in try await listener.waitForCallback() }
    let response = try await ProviderCheckLoopbackExchange().send(request, port: port)
    let callback = try await waiting.value
    try providerCheckRequire(response.hasPrefix("HTTP/1.1 200") && callback.host == "127.0.0.1" &&
                             callback.port == Int(port) && callback.path == path,
                             "A valid callback reaches the actual allocated IPv4 listener after unrelated requests")

    let canceled = ProviderOAuthLoopbackListener(timeout: .seconds(10))
    _ = try await canceled.start()
    let pending = Task { @MainActor in try await canceled.waitForCallback() }
    await Task.yield()
    canceled.cancel()
    do {
        _ = try await pending.value
        throw ProviderCheckFailure.assertion("Canceled native listener must release its pending callback waiter")
    } catch ProviderOAuthError.canceled { }

    let expired = ProviderOAuthLoopbackListener(timeout: .milliseconds(500))
    _ = try await expired.start()
    do {
        _ = try await expired.waitForCallback()
        throw ProviderCheckFailure.assertion("Native callback timeout must release its pending waiter")
    } catch ProviderOAuthError.authorizationExpired { }
}

@MainActor
private func checkProviderCancelledCallback() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(fixture)
    await fixture.browser.presentationGate.suspendNextOperation()
    let connecting = Task { @MainActor in await fixture.connection.connect() }
    do {
        try await waitForProviderCheckGate(fixture.browser.presentationGate)
        let cancellations = await fixture.browser.cancellationCount
        fixture.connection.cancel()
        try await waitForProviderBrowserCancellation(fixture.browser, after: cancellations)
        await fixture.browser.presentationGate.release()
        await connecting.value
        try await waitForProviderCheckIdle(fixture.connection)
    } catch {
        await fixture.browser.presentationGate.release()
        await connecting.value
        throw error
    }
    try providerCheckRequire(fixture.connection.receipt == nil && !fixture.connection.hasSavedAuthorization &&
                             fixture.connection.phase != .ready,
                             "A browser callback arriving after cancellation cannot claim readiness")
    let canceledStorage = await fixture.vault.counts
    let canceledRequests = await fixture.http.snapshot
    let canceledBrowser = await fixture.browser.counts
    try providerCheckRequire(canceledStorage.grantCommits == 0 && canceledRequests.grants.isEmpty &&
                             canceledBrowser.canceled > 0,
                             "Cancel closes the matching browser and rejects the stale code before token exchange")
}

@MainActor
private func checkProviderCancelledStorageCommit() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(fixture)
    await fixture.vault.writeGate.suspendNextOperation()
    let connecting = Task { @MainActor in await fixture.connection.connect() }
    do {
        try await waitForProviderCheckGate(fixture.vault.writeGate)
        fixture.connection.cancel()
        try await waitForProviderWriteInvalidation(fixture.vault)
        await fixture.vault.writeGate.release()
        await connecting.value
        try await waitForProviderCheckIdle(fixture.connection)
    } catch {
        await fixture.vault.writeGate.release()
        await connecting.value
        throw error
    }
    let canceledCommits = await fixture.vault.grantCommitCount
    try providerCheckRequire(fixture.connection.receipt == nil && !fixture.connection.hasSavedAuthorization &&
                             canceledCommits == 0,
                             "A protected-storage completion after cancellation cannot recreate the grant")
}

@MainActor
private func checkProviderDisconnectedExchange() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(fixture)
    await fixture.http.tokenGate.suspendNextOperation()
    let connecting = Task { @MainActor in await fixture.connection.connect() }
    var disconnecting: Task<Void, Never>?
    do {
        try await waitForProviderCheckGate(fixture.http.tokenGate)
        let cancellations = await fixture.browser.cancellationCount
        disconnecting = Task { @MainActor in await fixture.connection.disconnect() }
        try await waitForProviderBrowserCancellation(fixture.browser, after: cancellations)
        await fixture.http.tokenGate.release()
        await connecting.value
        await disconnecting?.value
    } catch {
        await fixture.http.tokenGate.release()
        await connecting.value
        await disconnecting?.value
        throw error
    }
    let disconnectedGrant = await fixture.vault.contains(.grant, for: fixture.identity)
    try providerCheckRequire(fixture.connection.phase == .disconnected && fixture.connection.receipt == nil &&
                             !fixture.connection.hasSavedAuthorization &&
                             !disconnectedGrant,
                             "Disconnect clears the grant and rejects an obsolete token response")
}

@MainActor
private func checkProviderCancelledCapabilities() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(fixture)
    await fixture.validator.validationGate.suspendNextOperation()
    let connecting = Task { @MainActor in await fixture.connection.connect() }
    do {
        try await waitForProviderCheckGate(fixture.validator.validationGate)
        fixture.connection.cancel()
        await fixture.validator.validationGate.release()
        await connecting.value
        try await waitForProviderCheckIdle(fixture.connection)
    } catch {
        await fixture.validator.validationGate.release()
        await connecting.value
        throw error
    }
    try providerCheckRequire(fixture.connection.receipt == nil && fixture.connection.phase != .ready,
                             "An MCP catalog completion after cancellation cannot publish its stale receipt")
    await fixture.connection.disconnect()
    let retainedGrant = await fixture.vault.contains(.grant, for: fixture.identity)
    try providerCheckRequire(!fixture.connection.hasSavedAuthorization &&
                             !retainedGrant,
                             "Disconnect removes the local fixture grant without claiming remote revocation")
}

@MainActor
private func checkProviderStorageFailures() async throws {
    let fixture = try ProviderCheckHarness(provider: .github)
    try await configureProviderCheckGitHub(fixture)
    await fixture.vault.rejectWrites(to: .grant)
    await fixture.connection.connect()
    let failedSaveValidations = await fixture.validator.validationCount
    try providerCheckRequire(fixture.connection.phase == .failed && fixture.connection.error != nil &&
                             fixture.connection.receipt == nil && !fixture.connection.hasSavedAuthorization &&
                             failedSaveValidations == 0,
                             "Protected grant-save failure is visible and prevents MCP readiness")
    await fixture.vault.rejectWrites(to: nil)
    await fixture.connection.connect()
    try providerCheckRequire(fixture.connection.phase == .ready, "Connection can recover after protected-storage availability returns")
    await fixture.vault.rejectWrites(to: .grant)
    await fixture.connection.disconnect()
    try providerCheckRequire(fixture.connection.receipt == nil && fixture.connection.phase != .ready &&
                             fixture.connection.error != nil,
                             "Protected grant-delete failure still clears active MCP readiness and reports the failure")
}

@MainActor
private func checkProviderLegacySeparation() async throws {
    let github = try ProviderCheckHarness(provider: .github)
    let linear = try ProviderCheckHarness(provider: .linear)
    let legacy = ProviderCheckLegacyCredentials()
    let initialValues = legacy.values
    let connections = ServiceConnections(credentialStore: legacy, transport: ProviderCheckLegacyHTTP(),
                                         githubMCP: github.connection, linearMCP: linear.connection)
    await connections.load()
    try providerCheckRequire(connections.hasGitHubCredential && connections.hasLinearCredential &&
                             connections.repository?.fullName == ServiceScope.repository &&
                             connections.project?.id == ServiceScope.linearProjectID,
                             "Legacy scoped API adapters remain available beside independent MCP connections")
    try await configureProviderCheckGitHub(github)
    await github.connection.connect()
    await linear.connection.connect()
    try providerCheckRequire(github.connection.phase == .ready && linear.connection.phase == .ready,
                             "Both MCP fixtures connect alongside existing API credentials")
    await connections.githubMCP.disconnect()
    await connections.linearMCP.disconnect()
    try providerCheckRequire(legacy.values == initialValues && legacy.writeCount == 0 &&
                             connections.hasGitHubCredential && connections.hasLinearCredential &&
                             connections.repository?.fullName == ServiceScope.repository &&
                             connections.project?.id == ServiceScope.linearProjectID,
                             "Removing MCP grants preserves legacy credential slots, API access and scoped data")
}

@MainActor
private func configureProviderCheckGitHub(_ fixture: ProviderCheckHarness) async throws {
    try providerCheckRequire(await fixture.connection.configureGitHub(clientID: "isolated-github-client",
                                                                      clientSecret: "isolated-configuration-only"),
                             "GitHub fixture registration can be protected without a provider request")
}

@MainActor
private func waitForProviderCheckIdle(_ connection: ProviderMCPConnection) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while connection.isBusy {
        guard clock.now < deadline else { throw ProviderCheckFailure.assertion("Provider cancellation retained a busy phase") }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private func waitForProviderBrowserCancellation(_ browser: ProviderCheckBrowser, after count: Int) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while await browser.cancellationCount <= count {
        guard clock.now < deadline else { throw ProviderCheckFailure.assertion("The provider browser was not canceled") }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private func waitForProviderWriteInvalidation(_ vault: ProviderCheckVault) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !(await vault.pendingWriteIsInvalidated) {
        guard clock.now < deadline else { throw ProviderCheckFailure.assertion("The pending protected write was not fenced") }
        try await Task.sleep(for: .milliseconds(2))
    }
}

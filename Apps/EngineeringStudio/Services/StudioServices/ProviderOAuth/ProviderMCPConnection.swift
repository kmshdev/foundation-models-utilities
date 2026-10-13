import EngineeringMCP
import Foundation
import Observation

/// UI-owned lifecycle over one actor-owned OAuth registration and MCP transport.
/// Neither the facade nor its capability receipt exposes a token to REST adapters.
@MainActor @Observable
package final class ProviderMCPConnection {
    package typealias CapabilityValidator = @Sendable
        (ProviderOAuthSession, ProviderOAuthAuthorizationReceipt, String, MCPClientLimits) async throws -> ProviderMCPReceipt

    package let provider: MCPProvider
    package private(set) var phase: ProviderMCPPhase = .disconnected
    package private(set) var error: String?
    package private(set) var receipt: ProviderMCPReceipt?
    package private(set) var hasSavedAuthorization = false
    package private(set) var grantedScopes: Set<String> = []
    package private(set) var githubClientID: String?
    package var isBusy: Bool { phase.isBusy }
    package var status: String {
        switch phase {
        case .disconnected: didDisconnect ? "Disconnected on this device" : "Not connected"
        case .restoring: "Reading saved authorization…"
        case .restored: "Saved authorization · Connect to verify"
        case .configurationRequired: "GitHub app registration required"
        case .authorizing: "Signing in…"
        case .connecting: "Verifying MCP connection…"
        case .refreshing: "Refreshing MCP connection…"
        case .configuring: "Saving app registration…"
        case .ready: "Connected · Read-only MCP"
        case .authorizationRequired: "Reconnect required"
        case .disconnecting: "Removing saved authorization…"
        case .cancelling: "Closing the connection…"
        case .failed: "MCP connection unavailable"
        }
    }
    private var didDisconnect = false
    @ObservationIgnored private let session: ProviderOAuthSession
    @ObservationIgnored private let browser: any ProviderOAuthBrowser
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let limits: MCPClientLimits
    @ObservationIgnored private let validateCapabilities: CapabilityValidator
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: Task<Bool, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?

    /// Factories create adapters only. Saved metadata is read explicitly by restore().
    package init(provider: MCPProvider, session: ProviderOAuthSession? = nil,
                 browser: (any ProviderOAuthBrowser)? = nil, appVersion: String = "0.1.0",
                 limits: MCPClientLimits = .init(), validateCapabilities: CapabilityValidator? = nil) {
        self.provider = provider
        self.session = session ?? ProviderOAuthNativeFactory.session(provider: provider)
        self.browser = browser ?? ProviderOAuthNativeFactory.browser(provider: provider)
        self.appVersion = appVersion
        self.limits = limits
        self.validateCapabilities = validateCapabilities ?? Self.verifyCapabilities
    }

    /// Launch restoration reads protected metadata, without browser or server traffic.
    package func restore() async {
        guard receipt == nil else { return }
        _ = await run(.restoring) { expected in
            try await self.loadSavedState(expected: expected)
            guard self.generation == expected else { return false }
            self.phase = self.savedPhase
            return true
        }
    }

    package func connect() async {
        _ = await run(.authorizing) { expected in
            if self.provider == .github {
                let clientID = try await self.session.githubClientID()
                guard self.generation == expected else { return false }
                self.githubClientID = clientID
                guard clientID != nil else { throw ProviderOAuthError.notConfigured }
            }
            let authorization = try await self.session.authorize(using: self.browser)
            try Task.checkCancellation()
            guard self.generation == expected else { return false }
            self.hasSavedAuthorization = true
            self.grantedScopes = authorization.scopes
            self.phase = .connecting
            try await self.verify(authorization, expected: expected)
            return self.generation == expected
        }
    }

    /// Silent refresh never presents a browser; expired grants require an explicit reconnect.
    package func refresh() async {
        _ = await run(.refreshing) { expected in
            try await self.session.prepareForRead()
            guard let authorization = try await self.session.restore() else { throw ProviderOAuthError.notAuthorized }
            try Task.checkCancellation()
            guard self.generation == expected else { return false }
            self.hasSavedAuthorization = true
            self.grantedScopes = authorization.scopes
            try await self.verify(authorization, expected: expected)
            return self.generation == expected
        }
    }

    @discardableResult
    package func configureGitHub(clientID: String, clientSecret: String) async -> Bool {
        guard provider == .github else { return false }
        return await run(.configuring) { expected in
            await self.session.close()
            try Task.checkCancellation()
            guard self.generation == expected else { return false }
            try await self.session.configureGitHub(clientID: clientID, clientSecret: clientSecret)
            guard self.generation == expected else { return false }
            do {
                try await self.loadSavedState(expected: expected)
                guard self.generation == expected else { return false }
                self.phase = self.savedPhase
            } catch ProviderOAuthError.configurationChanged {
                guard self.generation == expected else { return false }
                self.hasSavedAuthorization = false
                self.grantedScopes = []
                self.phase = .authorizationRequired
            }
            return true
        }
    }

    /// Cancellation preserves any previously committed grant. Its storage fence
    /// completes before the next connect/configuration may begin.
    package func cancel() {
        guard let previous = operation, phase != .disconnecting, phase != .cancelling else { return }
        let previousCleanup = cleanup
        let expected = UUID()
        generation = expected
        previous.cancel()
        operation = nil
        receipt = nil
        error = nil
        phase = .cancelling
        cleanup = Task { @MainActor [self] in
            if let previousCleanup { await previousCleanup.value }
            await session.cancel()
            await session.close()
            _ = await previous.value
            guard generation == expected else { return }
            do {
                try await loadSavedState(expected: expected)
                guard generation == expected else { return }
                phase = savedPhase
            } catch {
                guard generation == expected else { return }
                hasSavedAuthorization = false
                grantedScopes = []
                phase = .failed
                self.error = Self.safeDescription(error)
            }
            cleanup = nil
        }
    }

    package func disconnect() async { await finishConnection(removingGrant: true) }

    /// Application termination releases resources while retaining protected credentials.
    package func shutdown() async { await finishConnection(removingGrant: false) }

    private var savedPhase: ProviderMCPPhase {
        if hasSavedAuthorization { return .restored }
        return provider == .github && githubClientID == nil ? .configurationRequired : .disconnected
    }

    private func run(_ nextPhase: ProviderMCPPhase,
                     action: @escaping @MainActor (UUID) async throws -> Bool) async -> Bool {
        guard operation == nil, cleanup == nil, !isBusy, !Task.isCancelled else { return false }
        let expected = UUID()
        generation = expected
        receipt = nil
        error = nil
        didDisconnect = false
        phase = nextPhase
        let task = Task { @MainActor [self] in
            let succeeded: Bool
            do { succeeded = try await action(expected) }
            catch { succeeded = await fail(error, expected: expected) }
            guard generation == expected else { return false }
            operation = nil
            return succeeded
        }
        operation = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                self.cancel()
            }
        }
    }

    private func loadSavedState(expected: UUID) async throws {
        let clientID = provider == .github ? try await session.githubClientID() : nil
        guard generation == expected else { return }
        githubClientID = clientID
        let authorization = try await session.restore()
        guard generation == expected else { return }
        hasSavedAuthorization = authorization != nil
        grantedScopes = authorization?.scopes ?? []
    }

    private func verify(_ authorization: ProviderOAuthAuthorizationReceipt, expected: UUID) async throws {
        guard authorization.identity.provider == provider else { throw ProviderOAuthError.invalidMetadata }
        let verified = try await validateCapabilities(session, authorization, appVersion, limits)
        try Task.checkCancellation()
        guard generation == expected else { return }
        guard verified.identity == authorization.identity, verified.identity.endpoint == provider.endpoint,
              verified.toolCount >= 0 else { throw ProviderOAuthError.invalidMetadata }
        receipt = verified
        phase = .ready
    }

    private func fail(_ failure: any Error, expected: UUID) async -> Bool {
        guard generation == expected else { return false }
        await session.close()
        guard generation == expected else { return false }
        receipt = nil
        do { try await loadSavedState(expected: expected) }
        catch {
            if generation == expected {
                hasSavedAuthorization = false
                grantedScopes = []
            }
        }
        guard generation == expected else { return false }
        if failure is CancellationError || (failure as? ProviderOAuthError) == .canceled {
            error = nil
            phase = savedPhase
        } else {
            error = Self.safeDescription(failure)
            switch failure as? ProviderOAuthError {
            case .notConfigured: phase = .configurationRequired
            case .notAuthorized, .refreshExpired, .configurationChanged, .authorizationExpired:
                phase = .authorizationRequired
            default: phase = .failed
            }
        }
        return false
    }

    private func finishConnection(removingGrant: Bool) async {
        if removingGrant, phase == .disconnecting { _ = await operation?.value; return }
        let previous = operation
        let previousCleanup = cleanup
        let expected = UUID()
        generation = expected
        previous?.cancel()
        receipt = nil
        error = nil
        phase = removingGrant ? .disconnecting : .cancelling
        cleanup = nil
        let task = Task { @MainActor [self] in
            if let previousCleanup { await previousCleanup.value }
            await session.cancel()
            await session.close()
            if let previous { _ = await previous.value }
            guard generation == expected else { return false }
            do {
                if removingGrant { try await session.disconnect() }
                else { await session.close() }
                try await loadSavedState(expected: expected)
                guard generation == expected else { return false }
                didDisconnect = removingGrant
                phase = savedPhase
            } catch { _ = await fail(error, expected: expected) }
            guard generation == expected else { return false }
            operation = nil
            return true
        }
        operation = task
        _ = await task.value
    }

    private nonisolated static func safeDescription(_ error: any Error) -> String {
        if let providerError = error as? ProviderOAuthError { return providerError.localizedDescription }
        if error as? MCPClientError == .deadlineExceeded { return "The MCP connection timed out. Try connecting again." }
        return "The MCP connection could not be verified. Try connecting again."
    }

    private nonisolated static func verifyCapabilities(session: ProviderOAuthSession,
        authorization: ProviderOAuthAuthorizationReceipt, appVersion: String,
        limits: MCPClientLimits) async throws -> ProviderMCPReceipt {
        let policy = try MCPToolPolicy(identity: authorization.identity, operations: [])
        let client = try await session.makeReadOnlyClient(policy: policy, appVersion: appVersion, limits: limits)
        let initialization = try await client.initialize()
        let catalog = try await client.catalog()
        return .init(identity: initialization.identity, serverName: initialization.serverName,
                     serverVersion: initialization.serverVersion, protocolVersion: initialization.protocolVersion,
                     toolCount: catalog.tools.count, verifiedAt: Date())
    }
}

import EngineeringCore
import Foundation
import Observation
import Security

@MainActor @Observable
final class DeveloperRuntimeConnection: ExecutionRemoteHandler {
    private(set) var state = ExecutionSnapshot(connected: false, developers: [], records: [], blocker: nil)
    private(set) var repositoryURL: URL?
    private(set) var codexURL: URL?
    private(set) var isConnecting = false
    private(set) var isDispatching = false
    private(set) var isDisconnecting = false
    private(set) var error: String?
    private(set) var publicationErrors: [ExecutionTaskKey: String] = [:]
    private(set) var remoteOrigin: String?
    private(set) var sharingPort: UInt16?
    private(set) var isStartingSharing = false
    private(set) var remoteReachable = false
    var hasRuntime: Bool { coordinator != nil || remoteClient != nil }
    var needsAccountDisconnect: Bool { coordinator != nil || connectionKind == .local }
    private(set) var connectionKind: RuntimeConnectionKind?
    var connectedCount: Int { state.connected ? state.developers.count : 0 }
    var availableCount: Int { state.connected ? state.developers.filter { $0.isAvailable(at: .now) }.count : 0 }
    var isRemote: Bool { remoteClient != nil }
    var status: String {
        if isConnecting { return "Connecting…" }
        if state.connected { return "\(connectedCount) developers connected · \(availableCount) available" }
        if remoteReachable { return "Host connected · Developers offline" }
        return "Not connected"
    }
    var sharingOrigin: String? { sharingPort.map { "http://127.0.0.1:\($0)" } }
    @ObservationIgnored private var coordinator: ExecutionDeveloperCoordinator?
    @ObservationIgnored private var remoteClient: ExecutionRemoteClient?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var heldURLs: [URL] = []
    @ObservationIgnored private var sharingServer: ExecutionLoopbackServer?
    @ObservationIgnored private let credentials: any ConnectionCredentialStore
    @ObservationIgnored private let remoteTransport: any ServiceHTTPTransport
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var dispatchInFlight = false
    @ObservationIgnored private var publicationTask: Task<ExecutionPullRequestReceipt, any Error>?
    @ObservationIgnored private var publishingKey: ExecutionTaskKey?
    @ObservationIgnored private var savedReceipts: [ExecutionPullRequestReceipt] = []
    @ObservationIgnored private var automaticPublications: [ExecutionTaskKey] = []
    @ObservationIgnored private var autoPublicationTask: Task<Void, Never>?
    @ObservationIgnored private let receiptJournal: ExecutionReceiptJournal
    @ObservationIgnored private weak var connections: ServiceConnections?
    @ObservationIgnored private weak var store: StudioStore?
    @ObservationIgnored private var queuedPlans: [Outcome] = []
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var disconnectTask: Task<Void, Never>?

    init(credentials: any ConnectionCredentialStore = SystemConnectionKeychain(),
         remoteTransport: any ServiceHTTPTransport = ExecutionRemoteURLSessionTransport(),
         receiptJournal: ExecutionReceiptJournal = ExecutionReceiptJournal(url: URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio/Execution/pull-requests.json"))) {
        self.credentials = credentials; self.remoteTransport = remoteTransport; self.receiptJournal = receiptJournal
    }

    func configure(store: StudioStore, connections: ServiceConnections) { self.store = store; self.connections = connections }

    func load() async {
        guard !didLoad else { return }
        do { savedReceipts = try await receiptJournal.load(); didLoad = true; apply(state) }
        catch { self.error = error.localizedDescription; return }
        #if os(macOS)
        do {
            repositoryURL = try restoreBookmark("execution.repository")
            codexURL = try restoreBookmark("execution.codex")
        } catch { self.error = error.localizedDescription }
        #endif
    }

    func selectRepository(_ url: URL) {
        guard !hasRuntime, !isConnecting, !isDisconnecting else { return }
        do {
            #if os(macOS)
            try saveBookmark(url, key: "execution.repository")
            #endif
            repositoryURL = url; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func selectCodex(_ url: URL) {
        guard !hasRuntime, !isConnecting, !isDisconnecting else { return }
        do {
            #if os(macOS)
            try saveBookmark(url, key: "execution.codex")
            #endif
            codexURL = url; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func connectLocal(using account: ChatGPTConnection) async {
        guard !isConnecting, !isDisconnecting, !hasRuntime else { return }
        #if os(macOS)
        isConnecting = true; connectionKind = .local; error = nil
        generation = UUID(); let expected = generation
        defer { if generation == expected { isConnecting = false } }
        do {
            let model = try account.requireSelectedModel()
            guard let repositoryURL, let codexURL else {
                throw ExecutionError.invalidConfiguration("Choose the utilities repository folder and installed Codex binary below.")
            }
            heldURLs = [repositoryURL, codexURL].filter { $0.startAccessingSecurityScopedResource() }
            let support = URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio/Execution", isDirectory: true)
            let executable = try await RuntimeExecutableInstaller.install(codexURL, directory: support.appendingPathComponent("Binaries", isDirectory: true))
            try requireGeneration(expected)
            let process = ExecutionCodexProcess(configuration: .init(executableURL: executable,
                workingDirectory: repositoryURL, codexHome: support.appendingPathComponent("Codex", isDirectory: true)))
            let runtime = ExecutionDeveloperCoordinator(transport: process,
                worktrees: ExecutionGitWorktrees(repositoryURL: repositoryURL, worktreeDirectory: support.appendingPathComponent("Worktrees", isDirectory: true)),
                journal: ExecutionJournal(url: support.appendingPathComponent("receipts.json")),
                model: model, repositoryURL: repositoryURL, tokenProvider: account.session)
            coordinator = runtime
            try await runtime.start()
            guard generation == expected else { await runtime.stop(); return }
            apply(await runtime.snapshot())
            let changes = await runtime.updates()
            updatesTask = Task { [weak self] in
                for await snapshot in changes {
                    guard let self, self.generation == expected, !Task.isCancelled else { return }
                    self.apply(snapshot)
                }
            }
        } catch {
            if generation == expected {
                self.error = error.localizedDescription
                if let coordinator { await coordinator.stop(); apply(await coordinator.snapshot()) }
                coordinator = nil; connectionKind = nil; releaseURLs()
            }
        }
        #else
        error = "Connect to a shared developer runtime to execute work from iPhone."
        #endif
    }

    func connectRemote(url: String, pairingToken: String, accessID: String, accessSecret: String) async {
        guard !isConnecting, !isDisconnecting, !hasRuntime else { return }
        isConnecting = true; connectionKind = .remote; error = nil
        generation = UUID(); let expected = generation
        defer { if generation == expected { isConnecting = false } }
        do {
            guard let origin = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ExecutionError.invalidConfiguration("Enter the HTTPS address of your shared developer runtime.")
            }
            let access: ExecutionRemoteAccessCredential?
            if accessID.isEmpty && accessSecret.isEmpty { access = nil }
            else { access = try .init(clientID: accessID, clientSecret: accessSecret) }
            let client = try ExecutionRemoteClient(baseURL: origin, pairingToken: pairingToken, access: access, transport: remoteTransport)
            let snapshot = try await client.snapshot()
            guard generation == expected else { return }
            let credential = RuntimeRemoteCredential(origin: origin.absoluteString, token: pairingToken,
                accessID: accessID, accessSecret: accessSecret)
            try credentials.write(String(decoding: try JSONEncoder().encode(credential), as: UTF8.self), account: "developer-runtime.remote")
            remoteClient = client; remoteOrigin = origin.absoluteString; remoteReachable = true; apply(snapshot)
            updatesTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    guard let self, self.generation == expected else { return }
                    do {
                        let value = try await client.snapshot()
                        guard self.generation == expected else { return }
                        self.apply(value); self.remoteReachable = true; self.error = nil
                    } catch {
                        guard self.generation == expected else { return }
                        self.error = error.localizedDescription; self.remoteReachable = false
                        self.apply(.init(connected: false, developers: [], records: self.state.records,
                                           blocker: "Connection lost · Showing previous execution results"))
                    }
                }
            }
        } catch { if generation == expected { self.error = error.localizedDescription; connectionKind = nil } }
    }

    func reconnectRemote() async {
        do {
            guard let protected = try credentials.read("developer-runtime.remote") else { return }
            let credential = try JSONDecoder().decode(RuntimeRemoteCredential.self, from: Data(protected.utf8))
            await connectRemote(url: credential.origin, pairingToken: credential.token,
                                accessID: credential.accessID, accessSecret: credential.accessSecret)
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async {
        let expected = generation
        let remote = remoteClient; let local = coordinator
        do {
            let value: ExecutionSnapshot
            if let remote { value = try await remote.snapshot() }
            else if let local { try await local.refreshPresence(); value = await local.snapshot() }
            else { return }
            try requireGeneration(expected)
            apply(value); if remote != nil { remoteReachable = true }; error = nil
        } catch { if generation == expected, !isDisconnecting { self.error = error.localizedDescription } }
    }

    private func performRun(_ outcome: Outcome, store: StudioStore) async {
        guard !isDispatching, !isDisconnecting, let plan = outcome.plan else { return }
        let expected = generation
        isDispatching = true; error = nil
        defer { isDispatching = false }
        do {
            guard await store.flushPendingChanges() else { throw WorkspaceError.publicationNotSaved }
            try requireGeneration(expected)
            guard store.workspace.outcomes.first(where: { $0.id == outcome.id })?.plan == plan else {
                throw ExecutionError.invalidConfiguration("Assignments changed. Run the current plan instead.")
            }
            _ = try await dispatch(.init(outcomeID: outcome.id, outcome: outcome.text, plan: plan))
        } catch { if generation == expected, !isDisconnecting { self.error = error.localizedDescription } }
    }

    func run(_ outcome: Outcome, store: StudioStore) async {
        enqueue(outcome, store: store)
        await deliveryTask?.value
    }

    /// Only newly prepared plans enter this queue. Restored plans never dispatch implicitly.
    func enqueue(_ outcome: Outcome, store: StudioStore) {
        guard state.connected, outcome.plan != nil else { return }
        queuedPlans.removeAll { $0.id == outcome.id }
        queuedPlans.append(outcome)
        guard deliveryTask == nil else { return }
        let expected = generation
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.deliveryTask = nil }
            while !self.queuedPlans.isEmpty, self.generation == expected, !Task.isCancelled {
                let next = self.queuedPlans.removeFirst()
                guard store.workspace.outcomes.first(where: { $0.id == next.id })?.plan == next.plan else { continue }
                await self.performRun(next, store: store)
            }
        }
    }

    func hasDelivered(_ outcome: Outcome) -> Bool {
        guard let tasks = outcome.plan?.tasks else { return false }
        return tasks.allSatisfy { task in state.records.contains { $0.key.outcomeID == outcome.id && $0.task == task } }
    }

    func outcomeStatus(_ outcome: Outcome) -> String {
        guard let plan = outcome.plan else { return "Awaiting a plan" }
        let records = state.records.filter { $0.key.outcomeID == outcome.id && plan.tasks.contains($0.task) }
        guard !records.isEmpty else { return "\(plan.tasks.count) tasks · Not dispatched" }
        let completed = records.filter { $0.status == .completed }.count
        let blocked = records.filter { $0.status == .blocked || $0.status == .interrupted }.count
        return "\(completed) of \(plan.tasks.count) completed" + (blocked > 0 ? " · \(blocked) need attention" : "")
    }

    func record(outcomeID: UUID, taskID: String) -> ExecutionRecord? {
        state.records.first { $0.key.outcomeID == outcomeID && $0.key.taskID == taskID }
    }

    func snapshot() async throws -> ExecutionSnapshot { state }

    func dispatch(_ request: ExecutionRemoteDispatch) async throws -> ExecutionSnapshot {
        guard !dispatchInFlight else { throw ExecutionError.alreadyRunning }
        dispatchInFlight = true
        defer { dispatchInFlight = false }
        let expected = generation
        try requireGeneration(expected)
        let remote = remoteClient; let local = coordinator
        let value: ExecutionSnapshot
        if let remote { value = try await remote.dispatch(request) }
        else if let local {
            let current = await local.snapshot()
            try requireGeneration(expected)
            for task in request.plan.tasks {
                if let existing = current.records.first(where: { $0.key.outcomeID == request.outcomeID && $0.key.taskID == task.id }), existing.task != task {
                    throw ExecutionError.taskChanged
                }
            }
            if let store { try await store.acceptRemoteOutcome(request) }
            try requireGeneration(expected)
            try await local.dispatch(outcomeID: request.outcomeID, outcome: request.outcome, plan: request.plan)
            value = await local.snapshot()
        } else { throw ExecutionError.unavailable("Connect a developer runtime before running assignments.") }
        try requireGeneration(expected)
        apply(value)
        return value
    }

    func publish(_ key: ExecutionTaskKey) async throws -> ExecutionPullRequestReceipt {
        if let pending = publicationTask {
            guard publishingKey == key else { throw ExecutionPublicationError.alreadyPublishing }
            return try await pending.value
        }
        let expected = generation
        try requireGeneration(expected)
        guard let record = state.records.first(where: { $0.key == key }) else { throw ExecutionPublicationError.invalidRecord }
        let remote = remoteClient; let service = connections
        let parents = state.pullRequests.filter { $0.key.outcomeID == key.outcomeID }
        publishingKey = key
        let pending = Task { [weak self] in
            guard let self else { throw CancellationError() }
            let receipt: ExecutionPullRequestReceipt
            if let remote { receipt = try await remote.publish(key) }
            else if let service { receipt = try await service.publish(record: record, parents: parents) }
            else { throw ExecutionError.unavailable("Connect GitHub on the execution host before publishing a draft pull request.") }
            guard receipt.executionID == record.id, receipt.localCommitSHA == record.commitSHA else {
                throw ExecutionPublicationError.invalidRecord
            }
            // Persist a confirmed mutation even if the backend disconnects during its response.
            try await self.receiptJournal.save(receipt)
            self.savedReceipts = try await self.receiptJournal.load()
            self.apply(self.state)
            return receipt
        }
        publicationTask = pending
        defer { publicationTask = nil; publishingKey = nil }
        do {
            let receipt = try await pending.value
            publicationErrors[key] = nil
            return receipt
        } catch {
            publicationErrors[key] = error.localizedDescription
            throw error
        }
    }

    private func apply(_ value: ExecutionSnapshot) {
        let candidates = value.pullRequests + savedReceipts
        var found: Set<UUID> = []
        let receipts = candidates.filter { receipt in
            value.records.contains { $0.id == receipt.executionID && $0.key == receipt.key && $0.commitSHA == receipt.localCommitSHA }
                && found.insert(receipt.executionID).inserted
        }
        let finished = value.records.filter { record in
            record.status == .completed && record.commitSHA != nil &&
                state.records.contains { $0.id == record.id && $0.status != .completed } &&
                !receipts.contains { $0.executionID == record.id }
        }
        state = .init(connected: value.connected, developers: value.developers, records: value.records,
                      blocker: value.blocker, pullRequests: receipts)
        // Only a fresh completion on the actual host schedules a draft. Replayed history does not.
        if coordinator != nil, connections?.hasGitHubCredential == true {
            automaticPublications.append(contentsOf: finished.map(\.key))
            startAutomaticPublication()
        }
    }

    private func startAutomaticPublication() {
        guard autoPublicationTask == nil, !automaticPublications.isEmpty else { return }
        let expected = generation
        autoPublicationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.autoPublicationTask = nil }
            while !self.automaticPublications.isEmpty, self.generation == expected, !Task.isCancelled {
                let key = self.automaticPublications.removeFirst()
                do { _ = try await self.publish(key) }
                catch { self.publicationErrors[key] = error.localizedDescription }
            }
        }
    }

    func cancel(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        let expected = generation
        try requireGeneration(expected)
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.cancel(key) }
        else if let local = coordinator { try await local.cancel(key); value = await local.snapshot() }
        else { throw ExecutionError.unavailable("The developer runtime is disconnected.") }
        try requireGeneration(expected)
        apply(value)
        return value
    }

    func resume(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        let expected = generation
        try requireGeneration(expected)
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.resume(key) }
        else if let local = coordinator { try await local.resume(key); value = await local.snapshot() }
        else { throw ExecutionError.unavailable("The developer runtime is disconnected.") }
        try requireGeneration(expected)
        apply(value)
        return value
    }

    func restart() async throws -> ExecutionSnapshot {
        let expected = generation
        try requireGeneration(expected)
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.restart() }
        else if let local = coordinator { try await local.start(); value = await local.snapshot() }
        else { throw ExecutionError.notConnected }
        try requireGeneration(expected)
        apply(value)
        return value
    }

    @discardableResult
    func stop() async throws -> ExecutionSnapshot {
        let expected = generation
        try requireGeneration(expected)
        deliveryTask?.cancel(); queuedPlans = []
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.stop() }
        else if let local = coordinator { await local.stop(); value = await local.snapshot() }
        else { return state }
        try requireGeneration(expected)
        apply(value)
        return value
    }

    /// All callers await the same shutdown before an account or model can change.
    func disconnect() async {
        if let pending = disconnectTask { await pending.value; return }
        isDisconnecting = true
        generation = UUID(); isConnecting = false
        updatesTask?.cancel(); updatesTask = nil
        deliveryTask?.cancel(); queuedPlans = []
        autoPublicationTask?.cancel(); automaticPublications = []
        sharingServer?.stop(); sharingServer = nil; sharingPort = nil
        let local = coordinator; let remote = remoteClient; let delivery = deliveryTask
        let pending = Task { [weak self] in
            if let remote {
                do { _ = try await remote.stop() } catch { self?.error = error.localizedDescription }
            }
            if let local { await local.stop() }
            await delivery?.value
        }
        disconnectTask = pending
        await pending.value
        if let local { apply(await local.snapshot()) }
        coordinator = nil; remoteClient = nil; remoteOrigin = nil; remoteReachable = false; connectionKind = nil
        apply(.init(connected: false, developers: [], records: state.records, blocker: nil))
        releaseURLs()
        disconnectTask = nil; isDisconnecting = false
    }

    private func requireGeneration(_ expected: UUID) throws {
        try Task.checkCancellation()
        guard generation == expected, !isDisconnecting else { throw CancellationError() }
    }

    func shareRuntime() async {
        guard state.connected, !isRemote, sharingServer == nil, !isStartingSharing else { return }
        isStartingSharing = true
        let expected = generation
        defer { isStartingSharing = false }
        do {
            let token: String
            if let saved = try credentials.read("developer-runtime.sharing"), ExecutionRemoteLimits.validPairingToken(saved) { token = saved }
            else {
                token = try RuntimePairingToken.generate()
                try credentials.write(token, account: "developer-runtime.sharing")
            }
            let server = ExecutionLoopbackServer(pairingToken: token, handler: self)
            let port = try await server.start(port: 16080)
            guard generation == expected else { server.stop(); return }
            sharingPort = port; sharingServer = server; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func stopSharing() { sharingServer?.stop(); sharingServer = nil; sharingPort = nil }

    func reportError(_ error: any Error) { self.error = error.localizedDescription }

    func pairingCode() throws -> String? { try credentials.read("developer-runtime.sharing") }

    private func releaseURLs() {
        for url in heldURLs { url.stopAccessingSecurityScopedResource() }
        heldURLs = []
    }

    #if os(macOS)
    private func saveBookmark(_ url: URL, key: String) throws {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key)
    }

    private func restoreBookmark(_ key: String) throws -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try saveBookmark(url, key: key) }
        return url
    }
    #endif
}

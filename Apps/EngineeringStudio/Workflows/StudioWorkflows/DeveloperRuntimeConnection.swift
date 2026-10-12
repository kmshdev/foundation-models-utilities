import EngineeringWorkflows
import StudioServices
import EngineeringServices
import EngineeringCore
import Foundation
import Observation
import Security

@MainActor @Observable
package final class DeveloperRuntimeConnection: ExecutionRemoteHandler {
    package private(set) var state = ExecutionSnapshot(connected: false, developers: [], records: [], blocker: nil)
    package private(set) var repositoryURL: URL?
    package private(set) var codexURL: URL?
    package private(set) var isConnecting = false
    package private(set) var isDispatching = false
    package private(set) var isDisconnecting = false
    package private(set) var controlState: RuntimeControlState = .idle
    package private(set) var error: String?
    package private(set) var publicationErrors: [ExecutionTaskKey: String] = [:]
    package private(set) var remoteOrigin: String?
    package private(set) var sharingPort: UInt16?
    package private(set) var isStartingSharing = false
    package private(set) var remoteReachable = false
    package var hasRuntime: Bool { connectionKind != nil }
    package var needsAccountDisconnect: Bool { connectionKind == .local }
    package private(set) var connectionKind: RuntimeConnectionKind?
    package var connectedCount: Int { state.connected ? state.developers.count : 0 }
    package var availableCount: Int { state.connected ? state.developers.filter { $0.isAvailable(at: .now) }.count : 0 }
    package var isRemote: Bool { connectionKind == .remote }
    package var isControlling: Bool { controlState != .idle }
    package var controlStatus: String? {
        switch controlState {
        case .idle: nil
        case .pausing: "Pausing team…"
        case .restarting: "Restarting developers…"
        }
    }
    package var status: String {
        if let controlStatus { return controlStatus }
        if isConnecting { return "Connecting…" }
        if state.connected { return "\(connectedCount) developers connected · \(availableCount) available" }
        if remoteReachable { return "Host connected · Developers offline" }
        return "Not connected"
    }
    package var sharingOrigin: String? { sharingPort.map { "http://127.0.0.1:\($0)" } }
    @ObservationIgnored private var coordinator: ExecutionDeveloperCoordinator?
    @ObservationIgnored private var remoteClient: ExecutionRemoteClient?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    // A connection may survive Pause/Restart. Its read snapshots must not survive
    // the intervening control operation or restore the earlier worker state.
    @ObservationIgnored private var snapshotEpoch = UUID()
    @ObservationIgnored private var latestReadID = UUID()
    @ObservationIgnored private var controlTask: Task<ExecutionSnapshot, any Error>?
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

    package init(credentials: any ConnectionCredentialStore = SystemConnectionKeychain(),
         remoteTransport: any ServiceHTTPTransport = ExecutionRemoteURLSessionTransport(),
         receiptJournal: ExecutionReceiptJournal = ExecutionReceiptJournal(url: URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio/Execution/pull-requests.json"))) {
        self.credentials = credentials; self.remoteTransport = remoteTransport; self.receiptJournal = receiptJournal
    }

    package func configure(store: StudioStore, connections: ServiceConnections) { self.store = store; self.connections = connections }

    package func load() async {
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

    package func selectRepository(_ url: URL) {
        guard !hasRuntime, !isConnecting, !isDisconnecting else { return }
        do {
            #if os(macOS)
            try saveBookmark(url, key: "execution.repository")
            #endif
            repositoryURL = url; error = nil
        } catch { self.error = error.localizedDescription }
    }

    package func selectCodex(_ url: URL) {
        guard !hasRuntime, !isConnecting, !isDisconnecting else { return }
        do {
            #if os(macOS)
            try saveBookmark(url, key: "execution.codex")
            #endif
            codexURL = url; error = nil
        } catch { self.error = error.localizedDescription }
    }

    package func connectLocal(using account: ChatGPTConnection) async {
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
            await observeLocal(runtime, generation: expected, epoch: snapshotEpoch)
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

    package func connectRemote(url: String, pairingToken: String, accessID: String, accessSecret: String) async {
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
                    guard !self.isControlling, !self.dispatchInFlight else { continue }
                    let epoch = self.snapshotEpoch
                    let readID = self.beginSnapshotRead()
                    do {
                        let value = try await client.snapshot()
                        guard self.acceptsSnapshotRead(generation: expected, epoch: epoch, readID: readID) else { continue }
                        self.apply(value); self.remoteReachable = true; self.error = nil
                    } catch {
                        guard self.acceptsSnapshotRead(generation: expected, epoch: epoch, readID: readID) else { continue }
                        self.failSnapshotRead(error, remote: true)
                    }
                }
            }
        } catch { if generation == expected { self.error = error.localizedDescription; connectionKind = nil } }
    }

    package func reconnectRemote() async {
        do {
            guard let protected = try credentials.read("developer-runtime.remote") else { return }
            let credential = try JSONDecoder().decode(RuntimeRemoteCredential.self, from: Data(protected.utf8))
            await connectRemote(url: credential.origin, pairingToken: credential.token,
                                accessID: credential.accessID, accessSecret: credential.accessSecret)
        } catch { self.error = error.localizedDescription }
    }

    package func refresh() async {
        guard !isControlling, !dispatchInFlight, !isDisconnecting else { return }
        let expected = generation
        let epoch = snapshotEpoch
        let readID = beginSnapshotRead()
        let remote = remoteClient; let local = coordinator
        do {
            let value: ExecutionSnapshot
            if let remote { value = try await remote.snapshot() }
            else if let local { try await local.refreshPresence(); value = await local.snapshot() }
            else { return }
            guard acceptsSnapshotRead(generation: expected, epoch: epoch, readID: readID) else { return }
            apply(value); if remote != nil { remoteReachable = true }; error = nil
        } catch {
            if acceptsSnapshotRead(generation: expected, epoch: epoch, readID: readID) {
                failSnapshotRead(error, remote: remote != nil)
            }
        }
    }

    private func performRun(_ outcome: Outcome, store: StudioStore) async {
        guard !isDispatching, !isDisconnecting, !isControlling, let plan = outcome.plan else { return }
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
        } catch is CancellationError { }
        catch { if generation == expected, !isDisconnecting { self.error = error.localizedDescription } }
    }

    package func run(_ outcome: Outcome, store: StudioStore) async {
        enqueue(outcome, store: store)
        await deliveryTask?.value
    }

    /// Only newly prepared plans enter this queue. Restored plans never dispatch implicitly.
    package func enqueue(_ outcome: Outcome, store: StudioStore) {
        guard state.connected, !isControlling, !isDisconnecting, outcome.plan != nil else { return }
        queuedPlans.removeAll { $0.id == outcome.id }
        queuedPlans.append(outcome)
        startDeliveryIfNeeded(store: store)
    }

    private func startDeliveryIfNeeded(store: StudioStore) {
        guard state.connected, !isControlling, !isDisconnecting, !queuedPlans.isEmpty else { return }
        guard deliveryTask == nil else { return }
        let expected = generation
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.deliveryTask = nil
                // A cancelled delivery can finish after Restart. Start only the
                // fresh plans enqueued since that control operation completed.
                if self.generation == expected {
                    self.startDeliveryIfNeeded(store: store)
                }
            }
            while !self.queuedPlans.isEmpty, self.generation == expected, !Task.isCancelled {
                let next = self.queuedPlans.removeFirst()
                guard store.workspace.outcomes.first(where: { $0.id == next.id })?.plan == next.plan else { continue }
                await self.performRun(next, store: store)
            }
        }
    }

    package func planningContext(for outcome: Outcome) -> String {
        let available = state.connected ? state.developers.filter { $0.isAvailable(at: .now) }.map { $0.specialty.title } : []
        let receipts = state.records.filter { $0.key.outcomeID == outcome.id }.map { record in
            let commands = record.commands.map { "\($0.command) [exit \($0.exitCode.map(String.init) ?? "unreported")]" }.joined(separator: "; ")
            return "Task \(record.key.taskID): \(record.status.rawValue). \(record.summary.prefix(2000)) Blocker: \((record.blocker ?? "None").prefix(2000)). Commit: \(record.commitSHA ?? "None"). Commands: \(commands.prefix(2000))."
        }.joined(separator: "\n")
        return "Observed available developers: \(available.isEmpty ? "None" : available.joined(separator: ", ")).\nExecution receipts:\n\(receipts.prefix(16000))"
    }

    package func hasDelivered(_ outcome: Outcome) -> Bool {
        guard let tasks = outcome.plan?.tasks else { return false }
        return tasks.allSatisfy { task in state.records.contains { $0.key.outcomeID == outcome.id && $0.task == task } }
    }

    package func outcomeStatus(_ outcome: Outcome) -> String {
        guard let plan = outcome.plan else { return "Awaiting a plan" }
        let records = state.records.filter { $0.key.outcomeID == outcome.id && plan.tasks.contains($0.task) }
        guard !records.isEmpty else { return "\(plan.tasks.count) tasks · Not dispatched" }
        let completed = records.filter { $0.status == .completed }.count
        let blocked = records.filter { $0.status == .blocked || $0.status == .interrupted }.count
        return "\(completed) of \(plan.tasks.count) completed" + (blocked > 0 ? " · \(blocked) need attention" : "")
    }

    package func record(outcomeID: UUID, taskID: String) -> ExecutionRecord? {
        state.records.first { $0.key.outcomeID == outcomeID && $0.key.taskID == taskID }
    }

    package func snapshot() async throws -> ExecutionSnapshot { state }

    package func dispatch(_ request: ExecutionRemoteDispatch) async throws -> ExecutionSnapshot {
        guard !dispatchInFlight, !isControlling else { throw ExecutionError.alreadyRunning }
        dispatchInFlight = true
        defer { dispatchInFlight = false }
        let expected = generation
        try requireGeneration(expected)
        let epoch = beginSnapshotMutation()
        let remote = remoteClient; let local = coordinator
        let value: ExecutionSnapshot
        if let remote { value = try await remote.dispatch(request) }
        else if let local {
            let current = await local.snapshot()
            try requireSnapshotMutation(generation: expected, epoch: epoch)
            for task in request.plan.tasks {
                if let existing = current.records.first(where: { $0.key.outcomeID == request.outcomeID && $0.key.taskID == task.id }), existing.task != task {
                    throw ExecutionError.taskChanged
                }
            }
            if let store { try await store.acceptRemoteOutcome(request) }
            try requireSnapshotMutation(generation: expected, epoch: epoch)
            try await local.dispatch(outcomeID: request.outcomeID, outcome: request.outcome, plan: request.plan)
            value = await local.snapshot()
        } else { throw ExecutionError.unavailable("Connect a developer runtime before running assignments.") }
        try requireSnapshotMutation(generation: expected, epoch: epoch)
        _ = beginSnapshotMutation()
        apply(value)
        return value
    }

    package func publish(_ key: ExecutionTaskKey) async throws -> ExecutionPullRequestReceipt {
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

    package func cancel(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        guard !isControlling else { throw ExecutionError.alreadyRunning }
        let expected = generation
        try requireGeneration(expected)
        let epoch = beginSnapshotMutation()
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.cancel(key) }
        else if let local = coordinator { try await local.cancel(key); value = await local.snapshot() }
        else { throw ExecutionError.unavailable("The developer runtime is disconnected.") }
        try requireSnapshotMutation(generation: expected, epoch: epoch)
        _ = beginSnapshotMutation()
        apply(value)
        return value
    }

    package func resume(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot {
        guard !isControlling else { throw ExecutionError.alreadyRunning }
        let expected = generation
        try requireGeneration(expected)
        let epoch = beginSnapshotMutation()
        let value: ExecutionSnapshot
        if let remote = remoteClient { value = try await remote.resume(key) }
        else if let local = coordinator { try await local.resume(key); value = await local.snapshot() }
        else { throw ExecutionError.unavailable("The developer runtime is disconnected.") }
        try requireSnapshotMutation(generation: expected, epoch: epoch)
        _ = beginSnapshotMutation()
        apply(value)
        return value
    }

    package func restart() async throws -> ExecutionSnapshot {
        try await performControl(.restarting)
    }

    @discardableResult
    package func stop() async throws -> ExecutionSnapshot {
        try await performControl(.pausing)
    }

    /// Repeated identical controls share one acknowledgment. An opposite control
    /// cannot begin until that acknowledgment arrives, while Pause can interrupt
    /// an already-dispatched turn without waiting for its delivery response.
    private func performControl(_ action: RuntimeControlState) async throws -> ExecutionSnapshot {
        if let pending = controlTask {
            guard controlState == action else { throw ExecutionError.alreadyRunning }
            return try await pending.value
        }
        let expected = generation
        try requireGeneration(expected)
        guard !isConnecting else { throw ExecutionError.alreadyRunning }
        let remote = remoteClient; let local = coordinator
        guard remote != nil || local != nil else {
            if action == .pausing { return state }
            throw ExecutionError.notConnected
        }
        let epoch = beginSnapshotMutation()
        controlState = action
        if action == .pausing { deliveryTask?.cancel(); queuedPlans = [] }
        // A new subscription after acknowledgment starts with the coordinator's
        // current snapshot, so buffered pre-Pause values cannot restore presence.
        if local != nil { updatesTask?.cancel(); updatesTask = nil }
        let pending = Task { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                let value: ExecutionSnapshot
                if let remote {
                    value = action == .pausing ? try await remote.stop() : try await remote.restart()
                } else if let local {
                    if action == .pausing { await local.stop() }
                    else { try await local.start() }
                    value = await local.snapshot()
                } else { throw ExecutionError.notConnected }
                try self.requireSnapshotMutation(generation: expected, epoch: epoch)
                let acknowledgedEpoch = self.beginSnapshotMutation()
                self.apply(value)
                if remote != nil { self.remoteReachable = true }
                self.error = nil
                if let local { await self.observeLocal(local, generation: expected, epoch: acknowledgedEpoch) }
                return self.state
            } catch {
                if self.generation == expected, self.snapshotEpoch == epoch, !self.isDisconnecting {
                    if let local {
                        self.apply(await local.snapshot())
                        await self.observeLocal(local, generation: expected, epoch: epoch)
                        self.error = error.localizedDescription
                    } else { self.failSnapshotRead(error, remote: true) }
                }
                throw error
            }
        }
        controlTask = pending
        defer { controlTask = nil; controlState = .idle }
        return try await pending.value
    }

    /// All callers await the same shutdown before an account or model can change.
    package func disconnect() async {
        if let pending = disconnectTask { await pending.value; return }
        isDisconnecting = true
        generation = UUID(); isConnecting = false
        updatesTask?.cancel(); updatesTask = nil
        deliveryTask?.cancel(); queuedPlans = []
        autoPublicationTask?.cancel(); automaticPublications = []
        sharingServer?.stop(); sharingServer = nil; sharingPort = nil
        let local = coordinator; let remote = remoteClient; let delivery = deliveryTask; let control = controlTask
        let pending = Task { [weak self] in
            // A network control already in flight finishes before the explicit
            // disconnect stop; its obsolete reply cannot update this generation.
            _ = try? await control?.value
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

    private func beginSnapshotMutation() -> UUID {
        snapshotEpoch = UUID()
        return snapshotEpoch
    }

    private func requireSnapshotMutation(generation expected: UUID, epoch: UUID) throws {
        try requireGeneration(expected)
        guard snapshotEpoch == epoch else { throw CancellationError() }
    }

    private func beginSnapshotRead() -> UUID {
        latestReadID = UUID()
        return latestReadID
    }

    private func acceptsSnapshotRead(generation expected: UUID, epoch: UUID, readID: UUID) -> Bool {
        !Task.isCancelled && generation == expected && snapshotEpoch == epoch && latestReadID == readID &&
            !isDisconnecting && !isControlling
    }

    private func failSnapshotRead(_ failure: any Error, remote: Bool) {
        error = failure.localizedDescription
        if remote { remoteReachable = false }
        apply(.init(connected: remote ? false : state.connected, developers: [], records: state.records,
                    blocker: remote ? "Connection lost · Showing previous execution results" : "Availability could not be refreshed · Showing previous execution results",
                    pullRequests: state.pullRequests))
    }

    private func observeLocal(_ local: ExecutionDeveloperCoordinator, generation expected: UUID, epoch: UUID) async {
        let changes = await local.updates()
        guard generation == expected, snapshotEpoch == epoch, !isDisconnecting else { return }
        updatesTask = Task { [weak self] in
            for await snapshot in changes {
                guard let self, self.generation == expected, !Task.isCancelled else { return }
                guard !self.isControlling else { continue }
                self.apply(snapshot)
            }
        }
    }

    package func shareRuntime() async {
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

    package func stopSharing() { sharingServer?.stop(); sharingServer = nil; sharingPort = nil }

    package func reportError(_ error: any Error) { self.error = error.localizedDescription }

    package func pairingCode() throws -> String? { try credentials.read("developer-runtime.sharing") }

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

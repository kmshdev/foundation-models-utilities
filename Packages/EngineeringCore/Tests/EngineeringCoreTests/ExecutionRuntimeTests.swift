import Foundation
import Testing
@testable import EngineeringCore

private actor RuntimeTransport: ExecutionRPCTransport {
    var starts: [String?] = []
    var calls: [(String, ExecutionJSON)] = []
    var threads: [String] = []
    var loaded = true
    var stopped = 0
    var failNextTurn = false
    private var nextTurn = 0
    private var continuations: [AsyncStream<ExecutionNotification>.Continuation] = []
    func start(accessToken: String?) { starts.append(accessToken) }
    func request(method: String, params: ExecutionJSON) throws -> ExecutionJSON {
        calls.append((method, params))
        switch method {
        case "initialize": return .object([:])
        case "account/read": return .object(["account": .object(["type": .string("chatgpt")])])
        case "thread/start":
            let id = "thread-\(threads.count)"; threads.append(id)
            return .object(["thread": .object(["id": .string(id)])])
        case "thread/resume": return .object(["thread": .object(["id": params["threadId"]])])
        case "thread/loaded/list": return .object(["data": .array(loaded ? threads.map(ExecutionJSON.string) : [])])
        case "turn/start":
            if failNextTurn { failNextTurn = false; throw ExecutionError.timedOut("turn/start") }
            nextTurn += 1; return .object(["turn": .object(["id": .string("turn-\(nextTurn)")])])
        case "turn/interrupt": return .object([:])
        default: throw ExecutionError.rpcRejected(-32601)
        }
    }
    func notify(method: String, params: ExecutionJSON) {}
    func notifications() -> AsyncStream<ExecutionNotification> {
        let pair = AsyncStream<ExecutionNotification>.makeStream(); continuations.append(pair.continuation); return pair.stream
    }
    func stop() { stopped += 1 }
    func setLoaded(_ value: Bool) { loaded = value }
    func loseNextTurnReply() { failNextTurn = true }
    func calls(_ method: String) -> [ExecutionJSON] { calls.filter { $0.0 == method }.map(\.1) }
    func delta(thread: String, turn: String, text: String) {
        let event = ExecutionNotification(method: "item/agentMessage/delta", params: .object([
            "threadId": .string(thread), "turnId": .string(turn), "itemId": .string("final-result"), "delta": .string(text)]))
        for continuation in continuations { continuation.yield(event) }
    }
    func complete(thread: String, turn: String, status: String = "completed", items: [ExecutionJSON] = []) {
        var finalItems = items
        if !items.contains(where: { $0["type"].string == "agentMessage" }) {
            let input = calls.last { $0.0 == "turn/start" && $0.1["threadId"].string == thread }?.1["input"].array.first?["text"].string ?? ""
            let criteria = input.split(separator: "\n").filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }
            let result = ExecutionJSON.object(["disposition": .string("completed"), "summary": .string("Task implementation finished."),
                "acceptedCriteria": .array(criteria.map(ExecutionJSON.string)), "blocker": .string("")])
            let text = String(data: try! JSONEncoder().encode(result), encoding: .utf8)!
            finalItems.append(.object(["type": .string("agentMessage"), "text": .string(text)]))
        }
        let event = ExecutionNotification(method: "turn/completed", params: .object([
            "threadId": .string(thread), "turn": .object(["id": .string(turn), "status": .string(status), "items": .array(finalItems)])]))
        for continuation in continuations { continuation.yield(event) }
    }
}

private actor RuntimeWorktrees: ExecutionWorktreeManaging {
    var prepared: [(UUID, [String])] = []
    var failsScope = false
    func prepare(executionID: UUID, dependencyCommits: [String]) -> ExecutionWorktree {
        prepared.append((executionID, dependencyCommits))
        return .init(url: URL(fileURLWithPath: "/tmp/worktree-\(executionID)"), branch: "engineering/\(executionID)", baseSHA: String(repeating: "a", count: 40))
    }
    func verifyAndCommit(task: WorkTask, worktree: ExecutionWorktree) throws -> ExecutionGitReceipt {
        if failsScope { throw ExecutionError.scopeViolation(["Other.swift"]) }
        return .init(changedPaths: task.paths, commitSHA: String(repeating: "b", count: 40))
    }
    func setFailsScope() { failsScope = true }
    func dependencyCommits() -> [[String]] { prepared.map(\.1) }
}

private actor RuntimeJournal: ExecutionJournalStoring {
    var records: [ExecutionRecord] = []
    var fail = false
    var saveCount = 0
    init(records: [ExecutionRecord] = []) { self.records = records }
    func load() -> [ExecutionRecord] { records }
    func save(_ record: ExecutionRecord) throws {
        if fail { throw ExecutionError.persistenceFailed }
        saveCount += 1
        if let index = records.firstIndex(where: { $0.key == record.key }) { records[index] = record }
        else { records.append(record) }
    }
    func saveBatch(_ incoming: [ExecutionRecord]) throws {
        if fail { throw ExecutionError.persistenceFailed }
        for record in incoming { try save(record) }
    }
    func failWrites() { fail = true }
}

private actor RuntimeToken: ChatGPTTokenProviding {
    var value = "first-access-token"
    private var suspendNext = false
    private var waiting: CheckedContinuation<Void, Never>?
    func accessToken() async -> String {
        if suspendNext {
            suspendNext = false
            await withCheckedContinuation { waiting = $0 }
        }
        return value
    }
    func renew() { value = "second-access-token" }
    func suspendRenewal() { suspendNext = true }
    func isWaiting() -> Bool { waiting != nil }
    func releaseRenewal() { waiting?.resume(); waiting = nil }
}

private func runtimeTask(_ id: String, owner: Specialty = .architecture, path: String? = nil, dependencies: [String] = []) -> WorkTask {
    .init(id: id, title: id, owner: owner, paths: [path ?? "Sources/\(id).swift"], acceptance: ["Implement \(id)"], dependencies: dependencies, handoff: "Share verified diff and command receipts.")
}

private func runtime(_ transport: RuntimeTransport = .init(), worktrees: RuntimeWorktrees = .init(),
                     journal: RuntimeJournal = .init(), token: RuntimeToken? = nil) -> ExecutionDeveloperCoordinator {
    .init(transport: transport, worktrees: worktrees, journal: journal, model: "account-selected-model",
          repositoryURL: URL(fileURLWithPath: "/tmp/repository"), tokenProvider: token)
}

private func waitFor(_ runtime: ExecutionDeveloperCoordinator, _ predicate: @Sendable (ExecutionSnapshot) -> Bool) async throws -> ExecutionSnapshot {
    for _ in 0..<200 {
        let snapshot = await runtime.snapshot()
        if predicate(snapshot) { return snapshot }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Runtime did not reach expected state")
    return await runtime.snapshot()
}

@Suite struct ExecutionRuntimeTests {
    @Test func availabilityRequiresObservedThreadsAndDisappearsWhenNotLoaded() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport)
        #expect(await coordinator.snapshot().developers.isEmpty)
        try await coordinator.start()
        let snapshot = await coordinator.snapshot()
        #expect(snapshot.developers.count == 8)
        #expect(Set(snapshot.developers.map(\.threadID)).count == 8)
        #expect(snapshot.developers.allSatisfy { $0.isAvailable(at: .now) })
        await transport.setLoaded(false); try await coordinator.refreshPresence()
        #expect(await coordinator.snapshot().developers.isEmpty)
        await coordinator.stop()
    }

    @Test func oneOwnerRunsSequentiallyAndRepeatDispatchNeverDuplicates() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport), outcomeID = UUID()
        try await coordinator.start()
        let plan = WorkPlan(summary: "Two scopes", tasks: [runtimeTask("first"), runtimeTask("second")])
        try await coordinator.dispatch(outcomeID: outcomeID, outcome: "Build", plan: plan)
        #expect(await transport.calls("turn/start").count == 1)
        try await coordinator.dispatch(outcomeID: outcomeID, outcome: "Build", plan: plan)
        #expect(await transport.calls("turn/start").count == 1)
        let active = try #require(await coordinator.snapshot().records.first { $0.status == .running })
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID))
        _ = try await waitFor(coordinator) { $0.records.filter { $0.status == .running }.count == 1 && $0.records.contains { $0.status == .completed } }
        #expect(await transport.calls("turn/start").count == 2)
        await coordinator.stop()
    }

    @Test func independentSpecialtiesRunInParallelButCrossOutcomeScopesLeaseExclusively() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "A", plan: .init(summary: "A", tasks: [runtimeTask("a", path: "Shared.swift")]))
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "B", plan: .init(summary: "B", tasks: [runtimeTask("b", owner: .quality, path: "Shared.swift")]))
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "C", plan: .init(summary: "C", tasks: [runtimeTask("c", owner: .interface)]))
        #expect(await transport.calls("turn/start").count == 2)
        let records = await coordinator.snapshot().records
        #expect(records.first { $0.task.id == "b" }?.status == .queued)
        #expect(records.first { $0.task.id == "c" }?.status == .running)
        await coordinator.stop()
    }

    @Test func dependencyReceivesActualCommitContextAndObservedCommandExit() async throws {
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), coordinator = runtime(transport, worktrees: worktrees)
        let id = UUID(); try await coordinator.start()
        try await coordinator.dispatch(outcomeID: id, outcome: "A then B", plan: .init(summary: "Handoff", tasks: [
            runtimeTask("a"), runtimeTask("b", owner: .quality, dependencies: ["a"])]))
        let a = try #require(await coordinator.snapshot().records.first { $0.task.id == "a" })
        let command: ExecutionJSON = .object(["type": .string("commandExecution"), "id": .string("check-1"),
            "command": .string("swift test"), "cwd": .string("/tmp/worktree"), "status": .string("completed"),
            "exitCode": .number(1), "aggregatedOutput": .string("One failure")])
        await transport.complete(thread: try #require(a.threadID), turn: try #require(a.turnID), items: [command])
        let snapshot = try await waitFor(coordinator) { $0.records.contains { $0.task.id == "b" && $0.status == .running } }
        #expect(snapshot.records.first { $0.task.id == "a" }?.commands.first?.exitCode == 1)
        #expect(snapshot.records.first { $0.task.id == "b" }?.receivedHandoffs == [.init(outcomeID: id, taskID: "a")])
        #expect(await worktrees.dependencyCommits() == [[], [String(repeating: "b", count: 40)]])
        let inputs = await transport.calls("turn/start")
        #expect(inputs.last?["input"].array.first?["text"].string?.contains("swift test [exit 1]") == true)
        await coordinator.stop()
    }

    @Test func outsideScopeBlocksHandoffAndNeverCreatesSuccessReceipt() async throws {
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), coordinator = runtime(transport, worktrees: worktrees)
        await worktrees.setFailsScope(); try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Scope", plan: .init(summary: "Scope", tasks: [
            runtimeTask("a"), runtimeTask("b", owner: .quality, dependencies: ["a"])]))
        let active = try #require(await coordinator.snapshot().records.first { $0.isActive })
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID))
        let snapshot = try await waitFor(coordinator) { $0.records.allSatisfy { $0.status == .blocked } }
        #expect(snapshot.records.allSatisfy { $0.commitSHA == nil })
        #expect(await transport.calls("turn/start").count == 1)
        await coordinator.stop()
    }

    @Test func failedReservationWritePreventsDeliveryAndClearsPresence() async throws {
        let transport = RuntimeTransport(), journal = RuntimeJournal(), coordinator = runtime(transport, journal: journal)
        try await coordinator.start(); await journal.failWrites()
        await #expect(throws: ExecutionError.persistenceFailed) {
            try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        }
        #expect(await transport.calls("turn/start").isEmpty)
        // Reservation write failure must be visible and not suggest live capacity.
        #expect(await coordinator.snapshot().developers.isEmpty)
        await coordinator.stop()
    }

    @Test func restartRetainsInterruptedIdentityAndNeverRedelivers() async throws {
        let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "a")
        var pending = ExecutionRecord(key: key, outcome: "Build", task: runtimeTask("a"))
        pending.status = .running; pending.threadID = "old-thread"; pending.turnID = "old-turn"
        let transport = RuntimeTransport(), journal = RuntimeJournal(records: [pending]), coordinator = runtime(transport, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: key.outcomeID, outcome: "Build", plan: .init(summary: "Build", tasks: [pending.task]))
        #expect(await transport.calls("turn/start").isEmpty)
        #expect(await coordinator.snapshot().records.first?.status == .interrupted)
        #expect(await journal.load().first?.id == pending.id)
        await coordinator.stop()
    }

    @Test func renewedTokenRestartsAndResumesIdleThreadsWithoutEnteringPrompt() async throws {
        let transport = RuntimeTransport(), token = RuntimeToken(), coordinator = runtime(transport, token: token)
        try await coordinator.start(); await token.renew()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        #expect(await transport.starts == ["first-access-token", "second-access-token"])
        #expect(await transport.calls("thread/resume").count == 8)
        let input = await transport.calls("turn/start").first?["input"].array.first?["text"].string ?? ""
        #expect(!input.contains("access-token"))
        await coordinator.stop()
    }

    @Test func cancelWaitsForObservedInterruptionBeforeReleasingOwner() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a"), runtimeTask("b")]))
        let active = try #require(await coordinator.snapshot().records.first { $0.isActive })
        try await coordinator.cancel(active.key)
        #expect(await coordinator.snapshot().records.first { $0.key == active.key }?.status == .running)
        #expect(await transport.calls("turn/start").count == 1)
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID), status: "interrupted")
        _ = try await waitFor(coordinator) { $0.records.contains { $0.status == .cancelled } && $0.records.contains { $0.status == .running } }
        #expect(await transport.calls("turn/start").count == 2)
        await coordinator.stop()
    }

    @Test func resumedParentAutomaticallyUnblocksUntouchedDependencyChain() async throws {
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), journal = RuntimeJournal()
        let coordinator = runtime(transport, worktrees: worktrees, journal: journal), outcomeID = UUID()
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: outcomeID, outcome: "Recover the handoff chain", plan: .init(summary: "Chain", tasks: [
            runtimeTask("a"), runtimeTask("b", owner: .quality, dependencies: ["a"]),
            runtimeTask("c", owner: .interface, dependencies: ["b"])]))
        let reserved = await coordinator.snapshot().records
        let parent = try #require(reserved.first { $0.task.id == "a" })
        try await coordinator.cancel(parent.key)
        await transport.complete(thread: try #require(parent.threadID), turn: try #require(parent.turnID), status: "interrupted")
        let paused = try await waitFor(coordinator) { snapshot in
            snapshot.records.first { $0.task.id == "a" }?.status == .cancelled &&
            snapshot.records.filter { $0.status == .blocked }.count == 2
        }
        #expect(paused.records.filter { $0.status == .blocked }.allSatisfy {
            ExecutionDeveloperCoordinator.canRequeueWithoutDelivery($0)
        })
        #expect(await transport.calls("turn/start").count == 1)

        try await coordinator.resume(parent.key)
        let resumed = try #require(await coordinator.snapshot().records.first { $0.task.id == "a" })
        #expect(resumed.id == parent.id)
        #expect(resumed.threadID == parent.threadID)
        #expect(resumed.worktree == parent.worktree)
        #expect(await worktrees.dependencyCommits().count == 1)
        await transport.complete(thread: try #require(resumed.threadID), turn: try #require(resumed.turnID))
        let afterParent = try await waitFor(coordinator) { $0.records.contains { $0.task.id == "b" && $0.status == .running } }
        let child = try #require(afterParent.records.first { $0.task.id == "b" })
        #expect(child.id == reserved.first { $0.task.id == "b" }?.id)
        #expect(child.task == reserved.first { $0.task.id == "b" }?.task)
        #expect(child.receivedHandoffs == [parent.key])
        #expect(afterParent.records.first { $0.task.id == "c" }?.status == .blocked)
        #expect(await transport.calls("turn/start").count == 3)

        await transport.complete(thread: try #require(child.threadID), turn: try #require(child.turnID))
        let afterChild = try await waitFor(coordinator) { $0.records.contains { $0.task.id == "c" && $0.status == .running } }
        let descendant = try #require(afterChild.records.first { $0.task.id == "c" })
        #expect(descendant.id == reserved.first { $0.task.id == "c" }?.id)
        #expect(descendant.receivedHandoffs == [parent.key, child.key])
        #expect(await worktrees.dependencyCommits().count == 3)
        #expect(await transport.calls("turn/start").count == 4)
        #expect(await transport.calls("thread/resume").count == 1)
        #expect(await journal.load().count == 3)
        await coordinator.stop()
    }

    @Test func cancellingBeforeStartResumesSameReservationOnceAndRespectsScopeLease() async throws {
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), journal = RuntimeJournal()
        let coordinator = runtime(transport, worktrees: worktrees, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Existing owner", plan: .init(summary: "A", tasks: [
            runtimeTask("a", path: "Shared.swift")]))
        let waitingID = UUID(), plan = WorkPlan(summary: "B", tasks: [runtimeTask("b", owner: .quality, path: "Shared.swift")])
        try await coordinator.dispatch(outcomeID: waitingID, outcome: "Waiting owner", plan: plan)
        let initial = await coordinator.snapshot().records
        let owner = try #require(initial.first { $0.task.id == "a" })
        let reserved = try #require(initial.first { $0.task.id == "b" })
        #expect(reserved.status == .queued)
        try await coordinator.cancel(reserved.key)
        let cancelled = try #require(await coordinator.snapshot().records.first { $0.key == reserved.key })
        #expect(cancelled.status == .cancelled)
        #expect(ExecutionDeveloperCoordinator.canRequeueWithoutDelivery(cancelled))
        try await coordinator.resume(reserved.key)
        try await coordinator.dispatch(outcomeID: waitingID, outcome: "Waiting owner", plan: plan)
        let waiting = try #require(await coordinator.snapshot().records.first { $0.key == reserved.key })
        #expect(waiting.status == .queued)
        #expect(waiting.id == reserved.id && waiting.deliveryID == reserved.deliveryID)
        #expect(waiting.threadID == nil && waiting.worktree == nil)
        #expect(await transport.calls("turn/start").count == 1)
        #expect(await transport.calls("thread/resume").isEmpty)
        #expect(await worktrees.dependencyCommits().count == 1)

        await transport.complete(thread: try #require(owner.threadID), turn: try #require(owner.turnID))
        let delivered = try await waitFor(coordinator) { $0.records.contains { $0.key == reserved.key && $0.status == .running } }
        let resumed = try #require(delivered.records.first { $0.key == reserved.key })
        #expect(resumed.id == reserved.id && resumed.deliveryID == reserved.deliveryID)
        #expect(resumed.task == reserved.task)
        await #expect(throws: ExecutionError.self) { try await coordinator.resume(reserved.key) }
        try await coordinator.dispatch(outcomeID: waitingID, outcome: "Waiting owner", plan: plan)
        #expect(await transport.calls("turn/start").count == 2)
        #expect(await worktrees.dependencyCommits().count == 2)
        #expect(await journal.load().count == 2)
        await coordinator.stop()
    }

    @Test func dependencyRecoveryNeverPromotesUncertainDeliveryOrUnrelatedBlocker() async throws {
        let outcomeID = UUID(), parentKey = ExecutionTaskKey(outcomeID: outcomeID, taskID: "a")
        var parent = ExecutionRecord(key: parentKey, outcome: "Recovery", task: runtimeTask("a"))
        parent.status = .completed; parent.commitSHA = String(repeating: "b", count: 40)
        var uncertain = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "b"), outcome: "Recovery",
            task: runtimeTask("b", owner: .quality, dependencies: ["a"]))
        uncertain.status = .blocked; uncertain.blocker = ExecutionError.dependenciesFailed.localizedDescription
        uncertain.threadID = "retained-thread"
        uncertain.worktree = .init(url: URL(fileURLWithPath: "/tmp/uncertain-work"), branch: "engineering/retained", baseSHA: String(repeating: "a", count: 40))
        var unrelated = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "c"), outcome: "Recovery",
            task: runtimeTask("c", owner: .interface, dependencies: ["a"]))
        unrelated.status = .blocked; unrelated.blocker = "A required local tool is unavailable."
        var interrupted = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "d"), outcome: "Recovery", task: runtimeTask("d", owner: .platforms))
        interrupted.status = .interrupted
        let transport = RuntimeTransport(), journal = RuntimeJournal(records: [parent, uncertain, unrelated, interrupted])
        let coordinator = runtime(transport, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: outcomeID, outcome: "Recovery", plan: .init(summary: "Recovery", tasks: [
            parent.task, uncertain.task, unrelated.task, interrupted.task]))
        #expect(await transport.calls("turn/start").isEmpty)
        #expect(await journal.load() == [parent, uncertain, unrelated, interrupted])
        #expect(!ExecutionDeveloperCoordinator.canRequeueWithoutDelivery(uncertain))
        #expect(!ExecutionDeveloperCoordinator.canRequeueWithoutDelivery(interrupted))
        await #expect(throws: ExecutionError.self) { try await coordinator.resume(interrupted.key) }
        #expect(await transport.calls("turn/start").isEmpty)
        await coordinator.stop()
    }

    @Test func completedImmediateDependencyCannotHideInterruptedAncestor() async throws {
        let outcomeID = UUID()
        var ancestor = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "a"), outcome: "Recovery", task: runtimeTask("a"))
        ancestor.status = .interrupted; ancestor.threadID = "saved-thread"; ancestor.turnID = "saved-turn"
        var parent = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "b"), outcome: "Recovery",
            task: runtimeTask("b", owner: .quality, dependencies: ["a"]))
        parent.status = .completed; parent.commitSHA = String(repeating: "b", count: 40)
        var child = ExecutionRecord(key: .init(outcomeID: outcomeID, taskID: "c"), outcome: "Recovery",
            task: runtimeTask("c", owner: .interface, dependencies: ["b"]))
        child.status = .blocked; child.blocker = ExecutionError.dependenciesFailed.localizedDescription
        let transport = RuntimeTransport(), journal = RuntimeJournal(records: [ancestor, parent, child])
        let coordinator = runtime(transport, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: outcomeID, outcome: "Recovery", plan: .init(summary: "Recovery", tasks: [
            ancestor.task, parent.task, child.task]))
        #expect(await transport.calls("turn/start").isEmpty)
        #expect(await journal.load() == [ancestor, parent, child])
        #expect(await coordinator.snapshot().records.first { $0.key == child.key }?.status == .blocked)
        // An explicit retry must not acquire a lease or create a worktree while
        // a completed immediate parent's own ancestor is still unresolved.
        try await coordinator.resume(child.key)
        #expect(await transport.calls("turn/start").isEmpty)
        #expect(await coordinator.snapshot().records.first { $0.key == child.key }?.status == .blocked)
        await coordinator.stop()
    }

    @Test func failedRequeueWriteNeverDeliversOrReplacesCancelledIdentity() async throws {
        let transport = RuntimeTransport(), journal = RuntimeJournal(), coordinator = runtime(transport, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Queued reservation", plan: .init(summary: "Serial owner", tasks: [
            runtimeTask("a"), runtimeTask("b")]))
        let waiting = try #require(await coordinator.snapshot().records.first { $0.status == .queued })
        try await coordinator.cancel(waiting.key)
        await journal.failWrites()
        await #expect(throws: ExecutionError.persistenceFailed) { try await coordinator.resume(waiting.key) }
        let snapshot = await coordinator.snapshot()
        #expect(!snapshot.connected)
        #expect(snapshot.records.first { $0.key == waiting.key }?.status == .cancelled)
        #expect(snapshot.records.first { $0.key == waiting.key }?.id == waiting.id)
        #expect(await transport.calls("turn/start").count == 1)
        #expect(await transport.calls("thread/resume").isEmpty)
        #expect(await journal.load().first { $0.key == waiting.key }?.status == .cancelled)
        await coordinator.stop()
    }

    @Test func diskJournalPersistsFullTaskAndReceiptForAnotherInstance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("execution.json"), first = ExecutionJournal(url: url)
        var record = ExecutionRecord(key: .init(outcomeID: UUID(), taskID: "a"), outcome: "Build", task: runtimeTask("a"))
        record.status = .completed; record.commitSHA = String(repeating: "c", count: 40)
        try await first.save(record)
        let second = ExecutionJournal(url: url)
        #expect(try await second.load() == [record])
    }

    @Test func lostTurnReplyStopsUnknownWorkAndPreventsAutomaticRetry() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport), id = UUID()
        try await coordinator.start(); await transport.loseNextTurnReply()
        let plan = WorkPlan(summary: "Build", tasks: [runtimeTask("a")])
        try await coordinator.dispatch(outcomeID: id, outcome: "Build", plan: plan)
        #expect(await coordinator.snapshot().connected == false)
        #expect(await coordinator.snapshot().records.first?.status == .interrupted)
        #expect(await transport.calls("turn/start").count == 1)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: id, outcome: "Build", plan: plan)
        #expect(await transport.calls("turn/start").count == 1)
        await coordinator.stop()
    }

    @Test func interruptedWorkResumesSameConversationAndWorktree() async throws {
        let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "a")
        var pending = ExecutionRecord(key: key, outcome: "Build", task: runtimeTask("a"))
        pending.status = .interrupted; pending.threadID = "old-thread"; pending.turnID = "old-turn"
        pending.worktree = .init(url: URL(fileURLWithPath: "/tmp/retained-worktree"), branch: "engineering/retained", baseSHA: String(repeating: "a", count: 40))
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), journal = RuntimeJournal(records: [pending])
        let coordinator = runtime(transport, worktrees: worktrees, journal: journal)
        try await coordinator.start(); try await coordinator.resume(key)
        let calls = await transport.calls("turn/start")
        #expect(calls.count == 1)
        #expect(calls.first?["threadId"].string == "old-thread")
        #expect(calls.first?["cwd"].string == "/tmp/retained-worktree")
        #expect(await worktrees.dependencyCommits().isEmpty)
        #expect(await coordinator.snapshot().records.first?.id == pending.id)
        #expect(await coordinator.snapshot().records.first?.deliveryID != pending.deliveryID)
        await coordinator.stop()
    }

    @Test func completedTurnWithReportedBlockerNeverCommitsOrHandsOff() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        let active = try #require(await coordinator.snapshot().records.first { $0.isActive })
        let json = "{\"disposition\":\"blocked\",\"summary\":\"Needs SDK\",\"acceptedCriteria\":[],\"blocker\":\"Required Apple SDK is unavailable on this executor.\"}"
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID), items: [
            .object(["type": .string("agentMessage"), "text": .string(json)])])
        let snapshot = try await waitFor(coordinator) { $0.records.first?.status == .blocked }
        #expect(snapshot.records.first?.commitSHA == nil)
        #expect(snapshot.records.first?.blocker == "Required Apple SDK is unavailable on this executor.")
        await coordinator.stop()
    }

    @Test func incompleteAcceptanceResultCannotBecomeCompletion() async throws {
        let transport = RuntimeTransport(), coordinator = runtime(transport)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        let active = try #require(await coordinator.snapshot().records.first { $0.isActive })
        let json = "{\"disposition\":\"completed\",\"summary\":\"Partial work\",\"acceptedCriteria\":[],\"blocker\":\"\"}"
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID), items: [
            .object(["type": .string("agentMessage"), "text": .string(json)])])
        let snapshot = try await waitFor(coordinator) { $0.records.first?.status == .blocked }
        #expect(snapshot.records.first?.commitSHA == nil)
        await coordinator.stop()
    }

    @Test func transitiveHandoffIncludesEveryAncestorExactlyOnce() async throws {
        let transport = RuntimeTransport(), worktrees = RuntimeWorktrees(), coordinator = runtime(transport, worktrees: worktrees)
        let id = UUID(); try await coordinator.start()
        try await coordinator.dispatch(outcomeID: id, outcome: "A then B then C", plan: .init(summary: "Chain", tasks: [
            runtimeTask("a"), runtimeTask("b", owner: .quality, dependencies: ["a"]),
            runtimeTask("c", owner: .interface, dependencies: ["a", "b"])]))
        let a = try #require(await coordinator.snapshot().records.first { $0.task.id == "a" })
        await transport.complete(thread: try #require(a.threadID), turn: try #require(a.turnID))
        let afterA = try await waitFor(coordinator) { $0.records.contains { $0.task.id == "b" && $0.status == .running } }
        let b = try #require(afterA.records.first { $0.task.id == "b" })
        await transport.complete(thread: try #require(b.threadID), turn: try #require(b.turnID))
        let afterB = try await waitFor(coordinator) { $0.records.contains { $0.task.id == "c" && $0.status == .running } }
        let c = try #require(afterB.records.first { $0.task.id == "c" })
        #expect(c.receivedHandoffs == [.init(outcomeID: id, taskID: "a"), .init(outcomeID: id, taskID: "b")])
        #expect(await worktrees.dependencyCommits().last?.count == 2)
        await coordinator.stop()
    }

    @Test func streamedFinalJSONIsNotUserFacingOrWrittenForEveryToken() async throws {
        let transport = RuntimeTransport(), journal = RuntimeJournal(), coordinator = runtime(transport, journal: journal)
        try await coordinator.start()
        try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        let active = try #require(await coordinator.snapshot().records.first { $0.isActive })
        let writes = await journal.saveCount
        await transport.delta(thread: try #require(active.threadID), turn: try #require(active.turnID), text: "{\"disposition\":\"completed\",")
        let streamed = try await waitFor(coordinator) { $0.records.first?.summary == "The developer is preparing its result." }
        #expect(!streamed.records[0].summary.contains("disposition"))
        #expect(await journal.saveCount == writes)
        await transport.complete(thread: try #require(active.threadID), turn: try #require(active.turnID))
        let final = try await waitFor(coordinator) { $0.records.first?.status == .completed }
        #expect(final.records.first?.summary == "Task implementation finished.")
        #expect(final.records.first?.result?.acceptedCriteria == active.task.acceptance)
        #expect(await journal.saveCount > writes)
        await coordinator.stop()
    }

    @Test func journalBatchReservationIsAtomicAndInvalidBatchKeepsPreviousData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("execution.json"), journal = ExecutionJournal(url: url)
        let id = UUID()
        let first = ExecutionRecord(key: .init(outcomeID: id, taskID: "a"), outcome: "Build", task: runtimeTask("a"))
        let second = ExecutionRecord(key: .init(outcomeID: id, taskID: "b"), outcome: "Build", task: runtimeTask("b"))
        try await journal.saveBatch([first, second])
        let before = try Data(contentsOf: url)
        await #expect(throws: ExecutionError.persistenceFailed) { try await journal.saveBatch([first, first]) }
        #expect(try Data(contentsOf: url) == before)
        #expect(try await ExecutionJournal(url: url).load() == [first, second])
    }

    @Test func stopDuringTokenRenewalCannotReconnectOrDeliverQueuedWork() async throws {
        let transport = RuntimeTransport(), token = RuntimeToken(), coordinator = runtime(transport, token: token)
        try await coordinator.start(); await token.renew(); await token.suspendRenewal()
        let dispatch = Task {
            try await coordinator.dispatch(outcomeID: UUID(), outcome: "Build", plan: .init(summary: "Build", tasks: [runtimeTask("a")]))
        }
        for _ in 0..<200 {
            if await token.isWaiting() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await token.isWaiting())
        await coordinator.stop(); await token.releaseRenewal(); try await dispatch.value
        #expect(await coordinator.snapshot().connected == false)
        #expect(await transport.starts.count == 1)
        #expect(await transport.calls("turn/start").isEmpty)
        #expect(await coordinator.snapshot().blocker == nil)
    }
}

#if os(macOS) || os(Linux)
@Suite struct ExecutionGitWorktreeTests {
    @Test func realGitWorktreeCommitsOnlyScopeAndKeepsOriginalCheckoutUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = directory.appendingPathComponent("repository"), worktrees = directory.appendingPathComponent("worktrees")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try "initial\n".write(to: repository.appendingPathComponent("Owned.swift"), atomically: true, encoding: .utf8)
        try runGit(["init"], at: repository)
        try runGit(["config", "user.name", "Runtime Test"], at: repository)
        try runGit(["config", "user.email", "runtime@example.invalid"], at: repository)
        try runGit(["add", "."], at: repository)
        try runGit(["commit", "-m", "Initial"], at: repository)
        try runGit(["remote", "add", "origin", "https://github.com/\(ServiceScope.repository).git"], at: repository)
        let initialBranch = try runGit(["symbolic-ref", "--short", "HEAD"], at: repository).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", "-b", "fixture-dependency"], at: repository)
        try "dependency\n".write(to: repository.appendingPathComponent("Dependency.swift"), atomically: true, encoding: .utf8)
        try runGit(["add", "Dependency.swift"], at: repository)
        try runGit(["-c", "user.name=Dependency Author", "-c", "user.email=dependency@example.invalid", "commit", "-m", "Dependency implementation"], at: repository)
        let dependencyCommit = try runGit(["rev-parse", "HEAD"], at: repository).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", initialBranch], at: repository)
        try runGit(["config", "--unset", "user.name"], at: repository)
        try runGit(["config", "--unset", "user.email"], at: repository)
        try runGit(["config", "commit.gpgsign", "true"], at: repository)
        try runGit(["config", "gpg.program", "/nonexistent/engineering-test-gpg"], at: repository)
        let hooks = directory.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try "#!/bin/sh\nexit 7\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try runGit(["config", "core.hooksPath", hooks.path], at: repository)
        try runGit(["config", "core.fsmonitor", hook.path], at: repository)
        let originalConfiguration = try Data(contentsOf: repository.appendingPathComponent(".git/config"))
        let originalHead = try runGit(["rev-parse", "HEAD"], at: repository)
        let manager = ExecutionGitWorktrees(repositoryURL: repository, worktreeDirectory: worktrees)
        let tree = try await manager.prepare(executionID: UUID(), dependencyCommits: [])
        try "changed\n".write(to: tree.url.appendingPathComponent("Owned.swift"), atomically: true, encoding: .utf8)
        let receipt = try await manager.verifyAndCommit(task: runtimeTask("a", path: "Owned.swift"), worktree: tree)
        #expect(receipt.changedPaths == ["Owned.swift"])
        #expect(receipt.commitSHA != nil)
        #expect(try String(contentsOf: repository.appendingPathComponent("Owned.swift"), encoding: .utf8) == "initial\n")
        let firstCommit = try #require(receipt.commitSHA)
        #expect(try runGit(["show", "-s", "--format=%an <%ae>%n%cn <%ce>", firstCommit], at: tree.url) ==
            "Engineering Studio <engineering-studio@localhost>\nEngineering Studio <engineering-studio@localhost>\n")
        let next = try await manager.prepare(executionID: UUID(), dependencyCommits: [firstCommit])
        try "second\n".write(to: next.url.appendingPathComponent("Second.swift"), atomically: true, encoding: .utf8)
        let secondReceipt = try await manager.verifyAndCommit(task: runtimeTask("b", path: "Second.swift"), worktree: next)
        let secondCommit = try #require(secondReceipt.commitSHA)
        let receiver = try await manager.prepare(executionID: UUID(), dependencyCommits: [firstCommit, secondCommit, firstCommit])
        #expect(try String(contentsOf: receiver.url.appendingPathComponent("Owned.swift"), encoding: .utf8) == "changed\n")
        #expect(try String(contentsOf: receiver.url.appendingPathComponent("Second.swift"), encoding: .utf8) == "second\n")
        let authoredDependency = try await manager.prepare(executionID: UUID(), dependencyCommits: [dependencyCommit])
        #expect(try String(contentsOf: authoredDependency.url.appendingPathComponent("Dependency.swift"), encoding: .utf8) == "dependency\n")
        #expect(try runGit(["show", "-s", "--format=%an <%ae>%n%cn <%ce>", "HEAD"], at: authoredDependency.url) ==
            "Dependency Author <dependency@example.invalid>\nEngineering Studio <engineering-studio@localhost>\n")
        #expect(try Data(contentsOf: repository.appendingPathComponent(".git/config")) == originalConfiguration)
        #expect(try runGit(["rev-parse", "HEAD"], at: repository) == originalHead)
        let rejected = try await manager.prepare(executionID: UUID(), dependencyCommits: [])
        try "outside".write(to: rejected.url.appendingPathComponent("Other.swift"), atomically: true, encoding: .utf8)
        await #expect(throws: ExecutionError.scopeViolation(["Other.swift"])) {
            try await manager.verifyAndCommit(task: runtimeTask("a", path: "Owned.swift"), worktree: rejected)
        }
    }

    @discardableResult
    private func runGit(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try #require(String(data: data, encoding: .utf8))
    }
}

@Suite struct ExecutionCodexProcessTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ENGINEERING_CODEX_SMOKE_BINARY"] != nil))
    func liveCodexStdioHandshakeCreatesEightLoadedReadOnlyThreadsWithoutInference() async throws {
        let executable = try #require(ProcessInfo.processInfo.environment["ENGINEERING_CODEX_SMOKE_BINARY"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transport = ExecutionCodexProcess(configuration: .init(executableURL: URL(fileURLWithPath: executable),
            workingDirectory: directory, codexHome: directory.appendingPathComponent("codex-home")))
        do {
            // No credential is used or read. This proves live protocol/process
            // compatibility only; no turn is started and entitlement is not inferred.
            try await transport.start(accessToken: "non-entitlement-smoke-token")
            _ = try await transport.request(method: "initialize", params: .object([
                "clientInfo": .object(["name": .string("engineering_studio_smoke"), "version": .string("1.0")])]))
            try await transport.notify(method: "initialized", params: .object([:]))
            let catalog = try await transport.request(method: "model/list", params: .object([:]))
            let model = try #require(catalog["data"].array.first?["model"].string)
            var threads = Set<String>()
            for _ in Specialty.allCases {
                let response = try await transport.request(method: "thread/start", params: .object([
                    "model": .string(model), "cwd": .string(directory.path), "sandbox": .string("read-only"), "approvalPolicy": .string("never")]))
                threads.insert(try #require(response["thread"]["id"].string))
            }
            let loaded = try await transport.request(method: "thread/loaded/list", params: .object(["limit": .number(100)]))
            #expect(threads.count == 8)
            #expect(Set(loaded["data"].array.compactMap(\.string)).isSuperset(of: threads))
            await #expect(throws: ExecutionError.self) {
                try await transport.request(method: "engineering/unsupported", params: .object([:]))
            }
            await transport.stop()
            // The terminated child must be reaped, so an immediate later launch
            // cannot be refused by a stale isRunning cache or overlap its worktree.
            try await transport.start(accessToken: "non-entitlement-smoke-token")
            _ = try await transport.request(method: "initialize", params: .object([
                "clientInfo": .object(["name": .string("engineering_studio_smoke"), "version": .string("1.0")])]))
            try await transport.notify(method: "initialized", params: .object([:]))
            await transport.stop()
        } catch { await transport.stop(); throw error }
    }
}
#endif

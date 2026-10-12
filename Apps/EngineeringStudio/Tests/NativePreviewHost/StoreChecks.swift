@testable import WorkspaceFeature
@testable import StudioWorkflows
@testable import StudioServices
import StudioUI
import EngineeringWorkflows
import EngineeringServices
import EngineeringCore
import Foundation

/// Runs against the actual app store in the native preview host. These are state
/// regression checks, not UI interaction tests or model integration tests.
@MainActor
func checkStudioStore() async throws {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("workspace.json")
    let repository = WorkspaceRepository(url: url)
    var workspace = Workspace()
    let first = try workspace.recordOutcome("First outcome")
    let second = try workspace.recordOutcome("Second outcome")
    try await repository.save(workspace)
    let store = StudioStore(repository: repository)
    await store.load()
    try require(store.isLoaded, "Workspace loads")
    let firstDraft = store.draft(for: first, initialText: "First draft")
    let secondDraft = store.draft(for: second, initialText: "Second draft")
    firstDraft.text = "Preserved edit"
    try require(store.draft(for: first, initialText: "Do not replace") === firstDraft,
                "Selection changes preserve draft identity")
    try require(firstDraft.text == "Preserved edit" && secondDraft.text == "Second draft",
                "Outcome drafts stay independent")
    try require(await store.flushPendingChanges(), "Drafts reach disk")
    let relaunched = StudioStore(repository: repository)
    await relaunched.load()
    try require(relaunched.draft(for: first).text == "Preserved edit" &&
                relaunched.draft(for: second).text == "Second draft", "Relaunch restores each draft")
    try require(store.sendDraft(to: first), "Valid draft sends")
    try require(!store.sendDraft(to: first), "A repeated send cannot duplicate the message")
    try require(firstDraft.text.isEmpty && secondDraft.text == "Second draft",
                "Sending clears only its own draft")
    try require(store.workspace.messages.last?.outcomeID == first &&
                store.workspace.messages.last?.text == "Preserved edit", "Send keeps outcome ownership")
    try require(await store.flushPendingChanges(), "Sent message and cleared draft reach disk")
    try require(store.saveState == "Saved on this device", "Sent message reaches disk")
    let sentWorkspace = try await repository.load()
    try require(sentWorkspace.drafts[first] == nil && sentWorkspace.drafts[second] == "Second draft",
                "A saved message never leaves its sent text in the draft")
    try require(sentWorkspace.messages.filter { $0.text == "Preserved edit" }.count == 1,
                "Flush and retry do not duplicate messages")
    firstDraft.text = "Earlier edit"
    let firstFlush = Task { await store.flushPendingChanges() }
    await Task.yield()
    firstDraft.text = "Most recent edit"
    try require(await store.flushPendingChanges(), "Most recent edit reaches disk")
    _ = await firstFlush.value
    try require(try await repository.load().drafts[first] == "Most recent edit",
                "Overlapping flushes retain the newest draft")

    // A directory at the destination makes writes fail on all CI platforms,
    // including privileged runners where chmod-based failures are unreliable.
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    secondDraft.text = "Retain this after disk failure"
    try require(!(await store.flushPendingChanges()), "A failed write is reported")
    try require(secondDraft.text == "Retain this after disk failure" &&
                store.saveState == "Changes not saved", "Failed writes keep the draft and expose failure")
    firstDraft.text = "Message retained until disk recovers"
    try require(store.sendDraft(to: first), "A message can be accepted into memory during a disk failure")
    try require(!(await store.flushPendingChanges()), "An unsaved message is not reported as durable")
    try FileManager.default.removeItem(at: url)
    try require(await store.flushPendingChanges(), "A failed save can be retried")
    try require(store.failure == nil, "A successful retry clears its stale save failure")
    let recovered = StudioStore(repository: repository)
    await recovered.load()
    try require(recovered.draft(for: second).text == "Retain this after disk failure",
                "Retry recovers retained edits across relaunch")
    try require(recovered.draft(for: first).text.isEmpty &&
                recovered.workspace.messages.filter { $0.text == "Message retained until disk recovers" }.count == 1,
                "Retry commits the pending message and draft removal without resending")
    let unknown = UUID()
    let invalidDraft = store.draft(for: unknown, initialText: "Keep this text")
    try require(!store.sendDraft(to: unknown) && invalidDraft.text == "Keep this text",
                "Rejected send preserves the draft")

    let damagedURL = directory.appendingPathComponent("damaged.json")
    try Data("invalid JSON".utf8).write(to: damagedURL)
    let recoveringStore = StudioStore(repository: WorkspaceRepository(url: damagedURL))
    await recoveringStore.load()
    try require(!recoveringStore.isLoaded, "Corrupt data is not silently replaced")
    try JSONEncoder().encode(workspace).write(to: damagedURL)
    await recoveringStore.load()
    try require(recoveringStore.isLoaded && recoveringStore.workspace == workspace,
                "Failed loads can be retried after repair")
    try await checkAutomaticPlanning(in: directory)
    try await checkLinearIntakeAndPublication(in: directory)
    try await checkNewOutcomeDraft(in: directory)
    print("StudioStore regression checks passed: draft isolation, durable outcome creation, relaunch, atomic send, write ordering, failed-write retention, retry and load recovery.")
}

@MainActor
private func checkNewOutcomeDraft(in directory: URL) async throws {
    let url = directory.appendingPathComponent("new-outcome-draft.json")
    let repository = WorkspaceRepository(url: url)
    var workspace = Workspace()
    workspace.newOutcomeDraft = "Saved creation draft\nwith exact whitespace "
    workspace.revision = 1
    try await repository.save(workspace)
    let store = StudioStore(repository: repository)
    await store.load()
    let draft = store.newOutcomeDraft
    try require(draft.text == workspace.newOutcomeDraft && store.newOutcomeDraft === draft,
                "Creation presentation shares one restored, stable draft instance")
    draft.text = "  Build the native engineering coordinator\nwith handoffs  "
    try require(await store.flushPendingChanges(), "An unsubmitted new outcome reaches disk")
    let reopened = StudioStore(repository: repository)
    await reopened.load()
    try require(reopened.newOutcomeDraft.text == draft.text && reopened.workspace.outcomes.isEmpty,
                "Closing and reopening creation retains text without creating an outcome")
    guard let created = reopened.createOutcomeFromDraft() else {
        throw NSError(domain: "StudioStoreChecks", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Valid creation draft was rejected"])
    }
    try require(reopened.newOutcomeDraft.text.isEmpty && reopened.workspace.outcomes.count == 1 &&
                created.text == "Build the native engineering coordinator\nwith handoffs",
                "Creating an outcome clears only its accepted creation draft")
    try require(reopened.createOutcomeFromDraft() == nil && reopened.workspace.outcomes.count == 1,
                "Repeated creation cannot duplicate an already-cleared draft")
    try require(await reopened.flushPendingChanges(), "Created outcome and draft removal reach disk together")
    let completed = try await repository.load()
    try require(completed.newOutcomeDraft.isEmpty && completed.outcomes.first?.id == created.id &&
                completed.messages.count == 1, "Relaunch keeps the outcome and never restores its sent creation text")

    let unloaded = StudioStore(repository: repository)
    unloaded.newOutcomeDraft.text = "Keep this edit made before the workspace opens"
    try require(unloaded.createOutcomeFromDraft() == nil && !unloaded.newOutcomeDraft.text.isEmpty,
                "Rejected unloaded creation preserves its text")
    await unloaded.load()
    try require(unloaded.newOutcomeDraft.text == "Keep this edit made before the workspace opens",
                "A delayed load cannot overwrite an edit already owned by the creation draft")
    try require(await unloaded.flushPendingChanges(), "Pre-load edits reach disk after workspace recovery")
    try require(try await repository.load().newOutcomeDraft == unloaded.newOutcomeDraft.text,
                "Pre-load edits survive relaunch alongside the loaded outcomes")
    unloaded.newOutcomeDraft.text = " \n "
    try require(unloaded.createOutcomeFromDraft() == nil && unloaded.newOutcomeDraft.text == " \n ",
                "Empty creation is rejected without deleting editable whitespace")
}

@MainActor
private func checkLinearIntakeAndPublication(in directory: URL) async throws {
    let url = directory.appendingPathComponent("linear-intake.json")
    let repository = WorkspaceRepository(url: url)
    let provider = ControlledPlanner()
    let store = StudioStore(repository: repository, usesOnDeviceModel: true, planner: provider.call)
    await store.load()
    let sourceIssue = try linearIssue(id: UUID(), identifier: "ENG-1", title: "Build the native engineering room")
    try require(store.importIssue(sourceIssue), "Linear issue intake creates an outcome")
    try require(!store.importIssue(sourceIssue) && store.workspace.outcomes.count == 1,
                "Repeated imports do not create outcomes or messages")
    try await waitFor("Imported issue starts planning") { provider.calls.count == 1 }
    try require(provider.calls[0].outcome.contains(sourceIssue.identifier) &&
                provider.calls[0].outcome.contains("Imported requirements"), "Imported issue content reaches the planner")
    provider.finish(with: planResult("Imported issue plan"))
    try await waitFor("Imported plan completes") { !store.isPlanning }
    try require(await store.flushPendingChanges(), "Imported source and plan reach disk")
    let reloaded = StudioStore(repository: repository)
    await reloaded.load()
    try require(reloaded.hasImportedIssue(id: sourceIssue.id.lowercased()) && !reloaded.importIssue(sourceIssue),
                "Durable source identity prevents duplicate imports after relaunch")
    let outcome = reloaded.workspace.outcomes[0]
    guard let task = outcome.plan?.tasks.first else {
        throw NSError(domain: "StudioStoreChecks", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Imported plan has no task"])
    }
    let savedBeforeReservation = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var networkMayProceed = false
    do {
        _ = try await reloaded.prepareIssuePublication(outcomeID: outcome.id, task: task)
        networkMayProceed = true
    } catch WorkspaceError.publicationNotSaved { }
    try require(!networkMayProceed, "Failed reservation persistence prevents proceeding to a network mutation")
    guard let retained = reloaded.issueBinding(outcomeID: outcome.id, taskID: task.id) else {
        throw NSError(domain: "StudioStoreChecks", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed write lost its in-memory reservation"])
    }
    try require(retained.identifier == nil && retained.publishedTask == nil,
                "A reservation never claims a published issue")
    try FileManager.default.removeItem(at: url)
    try savedBeforeReservation.write(to: url, options: .atomic)
    let reserved = try await reloaded.prepareIssuePublication(outcomeID: outcome.id, task: task)
    try require(reserved.issueID == retained.issueID, "Retry retains the UUID allocated before the write failure")
    let diskReservation = try await repository.load().issueBinding(outcomeID: outcome.id, taskID: task.id)
    try require(diskReservation == reserved, "Publication permission follows a durable reservation")

    let resumed = StudioStore(repository: repository)
    await resumed.load()
    let sameReservation = try await resumed.prepareIssuePublication(outcomeID: outcome.id, task: task)
    try require(sameReservation.issueID == reserved.issueID,
                "A retry after app relaunch reconciles the same reserved issue UUID")
    let receipt = try linearIssue(id: reserved.issueID, identifier: "ENG-2", title: task.title)
    let beforeReceipt = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    do {
        try await resumed.recordIssuePublication(outcomeID: outcome.id, task: task, issue: receipt)
        try require(false, "Failed receipt persistence must throw")
    } catch WorkspaceError.publicationNotSaved { }
    try require(resumed.issueBinding(outcomeID: outcome.id, taskID: task.id)?.publishedTask == task,
                "Failed receipt persistence retains exact sent task in memory")
    try FileManager.default.removeItem(at: url)
    try beforeReceipt.write(to: url, options: .atomic)
    try await resumed.recordIssuePublication(outcomeID: outcome.id, task: task, issue: receipt)
    let receiptOnDisk = try await repository.load().issueBinding(outcomeID: outcome.id, taskID: task.id)
    try require(receiptOnDisk?.issueID == reserved.issueID && receiptOnDisk?.identifier == receipt.identifier &&
                receiptOnDisk?.webURL == receipt.webURL && receiptOnDisk?.publishedTask == task,
                "Receipt identity, URL and exact published snapshot survive disk reload")
    let unknownOutcome = UUID()
    do {
        _ = try await resumed.prepareIssuePublication(outcomeID: unknownOutcome, task: task)
        try require(false, "Unknown outcomes cannot reserve publication IDs")
    } catch WorkspaceError.missingOutcome { }
    try require(resumed.issueBinding(outcomeID: unknownOutcome, taskID: task.id) == nil,
                "Invalid scope never creates a ledger entry")
    print("Linear intake/publication checks passed: durable import deduplication, planning, saved reservation gate, stable UUID retry and receipt recovery.")
}

private func linearIssue(id: UUID, identifier: String, title: String) throws -> LinearIssue {
    let fields: [String: Any] = [
        "id": id.uuidString, "identifier": identifier, "title": title,
        "description": "Imported requirements", "priority": 2,
        "state": ["name": "Todo", "type": "unstarted"],
        "url": "https://linear.app/engineering/issue/\(identifier)"
    ]
    return try JSONDecoder().decode(LinearIssue.self, from: JSONSerialization.data(withJSONObject: fields))
}

@MainActor
private func checkAutomaticPlanning(in directory: URL) async throws {
    let provider = ControlledPlanner()
    let store = StudioStore(repository: WorkspaceRepository(url: directory.appendingPathComponent("planning.json")),
                            usesOnDeviceModel: true, planner: provider.call)
    await store.load()
    try require(store.submit("First planned outcome"), "New outcomes automatically request a plan")
    try await waitFor("Initial planner call") { provider.calls.count == 1 }
    let first = store.workspace.outcomes[0].id
    store.draft(for: first).text = "Include accessibility"
    try require(store.sendDraft(to: first), "Draft follow-up is accepted while planning")
    try require(store.send("Prioritize keyboard navigation", to: first), "Second follow-up is accepted")
    try require(store.submit("Second planned outcome"), "Other outcomes queue while planning")
    let second = store.workspace.outcomes[1].id
    try require(store.isQueuedForPlanning(second), "Waiting outcomes expose queued status")
    provider.finish(with: planResult("Obsolete plan"))
    try await waitFor("Coalesced follow-up planner call") { provider.calls.count == 2 }
    try require(store.workspace.outcomes[0].plan == nil &&
                !store.workspace.messages.contains { $0.text == "Obsolete plan" },
                "New context prevents an obsolete result from publishing")
    try require(provider.calls[1].outcome == "First planned outcome" &&
                provider.calls[1].context.contains("Include accessibility") &&
                provider.calls[1].context.contains("Prioritize keyboard navigation"),
                "Queued follow-ups coalesce with the latest complete context")
    provider.finish(with: planResult("Latest first plan"))
    try await waitFor("Other outcome planner call") { provider.calls.count == 3 }
    try require(!store.isQueuedForPlanning(second) && store.planningOutcomeID == second,
                "Queued status clears when the outcome becomes active")
    try require(provider.calls[2].outcome == "Second planned outcome" &&
                !provider.calls[2].context.contains("Include accessibility"),
                "Queued outcomes retain independent context")
    provider.finish(with: planResult("Second plan"))
    try await waitFor("Planning queue drains") { !store.isPlanning }
    try require(provider.calls.count == 3 && provider.maximumActiveCalls == 1 &&
                store.workspace.outcomes[0].plan?.summary == "Latest first plan" &&
                store.workspace.outcomes[1].plan?.summary == "Second plan",
                "One planner call runs at a time without dropping other outcomes")

    try require(store.send("Start a cancelled request", to: first), "Follow-up starts automatically")
    try await waitFor("Cancellable request starts") { provider.calls.count == 4 }
    try require(store.send("Queued first follow-up", to: first) &&
                store.send("Queued second follow-up", to: second), "Follow-ups queue during an active call")
    store.cancelPlanning()
    provider.finish(with: planResult("Cancelled plan")) // Provider deliberately ignores cancellation.
    try await waitFor("Cancelled worker exits") { !store.isPlanning }
    try require(provider.calls.count == 4 &&
                !store.workspace.messages.contains { $0.text == "Cancelled plan" },
                "Cancel clears queued work and rejects late results")

    store.plan(store.workspace.outcomes[0])
    try await waitFor("Manual retry starts") { provider.calls.count == 5 }
    try require(store.send("Queue before disabling", to: second), "Second outcome queues")
    let previousPreference = UserDefaults.standard.object(forKey: "usesOnDeviceModel")
    defer {
        if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: "usesOnDeviceModel") }
        else { UserDefaults.standard.removeObject(forKey: "usesOnDeviceModel") }
    }
    store.setOnDeviceModel(false)
    provider.finish(with: planResult("Disabled model result"))
    try await waitFor("Disabled worker exits") { !store.isPlanning }
    try require(store.send("Offline follow-up", to: first) && !store.isPlanning && provider.calls.count == 5,
                "Disabling planning clears the queue and accepts messages without model calls")
    try require(!store.workspace.messages.contains { $0.text == "Disabled model result" },
                "A disabled model cannot publish a late result")
    store.setOnDeviceModel(true)
    try require(store.send("Request before cancellation", to: first), "Planning can restart")
    try await waitFor("Restarted request begins") { provider.calls.count == 6 }
    store.cancelPlanning()
    try require(store.send("New work after cancellation", to: second), "New work can queue while cancellation unwinds")
    try require(provider.calls.count == 6, "A cancelled call still owns the provider until it exits")
    provider.finish(with: planResult("Late cancelled result"))
    try await waitFor("New request after cancellation starts") { provider.calls.count == 7 }
    try require(provider.calls[6].outcome == "Second planned outcome" && provider.maximumActiveCalls == 1,
                "A new worker starts only after the cancelled worker exits")
    provider.finish(with: planResult("Restarted second plan"))
    try await waitFor("Restarted queue drains") { !store.isPlanning }

    try require(store.send("Request that fails", to: first), "Error check begins")
    try await waitFor("Failing request starts") { provider.calls.count == 8 }
    try require(store.send("Continue other outcome", to: second), "Other work queues behind a failing call")
    provider.fail()
    try await waitFor("Queue continues after error") { provider.calls.count == 9 }
    try require(store.failure?.contains("Controlled planner failure") == true,
                "Current provider errors are reported")
    provider.finish(with: planResult("Plan after another outcome failed"))
    try await waitFor("Queue after error drains") { !store.isPlanning }
    try require(store.workspace.outcomes[1].plan?.summary == "Plan after another outcome failed",
                "One outcome failure does not drop another outcome's work")
    try require(await store.flushPendingChanges(), "Planning results and follow-ups are durable")

    var workspace = Workspace()
    let gatedID = try workspace.recordOutcome("Gated outcome")
    let destination = Question(prompt: "Which destination?")
    let budget = Question(prompt: "What budget?")
    let batch = QuestionBatch(outcomeID: gatedID, questions: [destination, budget])
    workspace.questions.append(batch)
    let repository = WorkspaceRepository(url: directory.appendingPathComponent("questions.json"))
    try await repository.save(workspace)
    let gatedProvider = ControlledPlanner()
    let gated = StudioStore(repository: repository, usesOnDeviceModel: true, planner: gatedProvider.call)
    await gated.load()
    try require(gated.send("Include the audit", to: gatedID), "Blocked outcomes still retain follow-ups")
    gated.answer(batch, answers: [destination.id: "Engineering group"])
    try require(!gated.isPlanning && gatedProvider.calls.isEmpty, "Partial answers keep the planner gated")
    gated.answer(batch, answers: [budget.id: "Existing resources"])
    try await waitFor("Complete answers trigger planning") { gatedProvider.calls.count == 1 }
    try require(gatedProvider.calls[0].context.contains("Engineering group") &&
                gatedProvider.calls[0].context.contains("Existing resources") &&
                gatedProvider.calls[0].context.contains("Include the audit"),
                "Planning resumes automatically with retained answers and follow-ups")
    gated.answer(batch, answers: [destination.id: ""])
    gatedProvider.finish(with: PlanningResult(plan: nil, questions: [Question(prompt: "Obsolete question")]))
    try await waitFor("Newly incomplete answers gate the worker") { !gated.isPlanning }
    try require(gated.workspace.questions.count == 1, "Obsolete generated questions are discarded too")
    gated.answer(batch, answers: [destination.id: "Private engineering group"])
    try await waitFor("Corrected answers trigger latest context") { gatedProvider.calls.count == 2 }
    try require(gatedProvider.calls[1].context.contains("Private engineering group"), "Corrected answer replaces old context")
    gatedProvider.finish(with: planResult("Answered plan"))
    try await waitFor("Answered plan finishes") { !gated.isPlanning }
    try require(gated.workspace.outcomes[0].plan?.summary == "Answered plan", "Plan attaches to the answered outcome")
    try require(await gated.flushPendingChanges(), "Answered plan reaches disk")
    print("Automatic planning checks passed: latest context, coalescing, serialization, independent outcomes, cancellation, model disable and answer gating.")
}

@MainActor
private final class ControlledPlanner {
    struct Call { let outcome: String; let context: String }
    private(set) var calls: [Call] = []
    private(set) var maximumActiveCalls = 0
    private var pending: [CheckedContinuation<PlanningResult, any Error>] = []

    func call(outcome: String, context: String) async throws -> PlanningResult {
        calls.append(Call(outcome: outcome, context: context))
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            maximumActiveCalls = max(maximumActiveCalls, pending.count)
        }
    }

    func finish(with result: PlanningResult) { pending.removeFirst().resume(returning: result) }

    func fail() {
        pending.removeFirst().resume(throwing: NSError(domain: "ControlledPlanner", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Controlled planner failure"]))
    }
}

private func planResult(_ summary: String) -> PlanningResult {
    PlanningResult(plan: WorkPlan(summary: summary, tasks: [
        WorkTask(id: "interface", title: "Build interface", owner: .interface, paths: ["Apps/Room.swift"],
                 acceptance: ["Verify keyboard navigation"], dependencies: [], handoff: "Share changed files and test results")
    ]), questions: [])
}

@MainActor
private func waitFor(_ message: String, condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    try require(false, "Timed out: \(message)")
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "StudioStoreChecks", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}

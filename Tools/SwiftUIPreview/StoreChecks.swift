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
    print("StudioStore regression checks passed: draft isolation, relaunch, atomic send, write ordering, failed-write retention, retry and load recovery.")
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "StudioStoreChecks", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}

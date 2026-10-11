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
    try require(store.sendDraft(to: first), "Valid draft sends")
    try require(firstDraft.text.isEmpty && secondDraft.text == "Second draft",
                "Sending clears only its own draft")
    try require(store.workspace.messages.last?.outcomeID == first &&
                store.workspace.messages.last?.text == "Preserved edit", "Send keeps outcome ownership")
    for _ in 0..<100 {
        if store.saveState != "Saving…" { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    try require(store.saveState == "Saved on this device", "Sent message reaches disk")
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
    print("StudioStore regression checks passed: draft isolation, retention, send ownership, disk save and load recovery.")
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "StudioStoreChecks", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}

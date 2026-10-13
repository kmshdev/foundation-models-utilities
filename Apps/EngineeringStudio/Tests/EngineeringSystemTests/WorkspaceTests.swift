import Foundation
import Testing
@testable import EngineeringCore

private func task(_ id: String, path: String, dependencies: [String] = []) -> WorkTask {
    .init(id: id, title: "Implement \(id)", owner: .interface, paths: [path],
          acceptance: ["Verify \(id) behavior"], dependencies: dependencies,
          handoff: "Share commit, changed files, test commands and results.")
}

@Test func outcomeThreadsDoNotMixMessagesOrCreateExtraOutcomes() throws {
    var workspace = Workspace()
    let first = try workspace.recordOutcome("First outcome")
    let second = try workspace.recordOutcome("Second outcome")
    try workspace.recordMessage("  Prioritize accessibility  ", for: first)
    try workspace.attach(.init(summary: "Second plan", tasks: [task("b", path: "B")]), to: second)
    #expect(workspace.outcomes.count == 2)
    #expect(workspace.messages.filter { $0.outcomeID == first }.map(\.text) == ["First outcome", "Prioritize accessibility"])
    #expect(workspace.messages.filter { $0.outcomeID == second }.map(\.text) == ["Second outcome", "Second plan"])
    let unchanged = workspace
    #expect(throws: WorkspaceError.emptyMessage) { try workspace.recordMessage(" \n ", for: first) }
    #expect(throws: WorkspaceError.missingOutcome) { try workspace.recordMessage("Hello", for: UUID()) }
    #expect(workspace == unchanged)
    #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace)) == workspace)
}

@Test func legacyMessagesRemainReadableWithoutGuessingAnOutcome() throws {
    let message = RoomMessage(author: .user, text: "Earlier conversation")
    let data = try JSONEncoder().encode(message)
    var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    fields.removeValue(forKey: "outcomeID")
    let restored = try JSONDecoder().decode(RoomMessage.self, from: JSONSerialization.data(withJSONObject: fields))
    #expect(restored.outcomeID == nil)
    #expect(restored.text == message.text)
}

@Test func legacyWorkspacesLoadWithoutDrafts() throws {
    var workspace = Workspace()
    _ = try workspace.recordOutcome("Existing outcome")
    let data = try JSONEncoder().encode(workspace)
    var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    fields.removeValue(forKey: "drafts")
    fields.removeValue(forKey: "newOutcomeDraft")
    fields.removeValue(forKey: "issueBindings")
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: fields))
    #expect(restored == workspace)
    #expect(restored.drafts.isEmpty)
    #expect(restored.newOutcomeDraft.isEmpty)
    #expect(restored.issueBindings.isEmpty)
    #expect(restored.outcomes.first?.source == nil)
}

@Test func newOutcomeDraftSurvivesReloadAndClearsWithCreatedOutcome() async throws {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
    var workspace = Workspace()
    workspace.newOutcomeDraft = "  Build the engineering room\nwith preserved whitespace  "
    workspace.revision += 1
    try await repository.save(workspace)
    var restored = try await repository.load()
    #expect(restored.newOutcomeDraft == workspace.newOutcomeDraft)
    let id = try restored.recordOutcome(restored.newOutcomeDraft)
    restored.newOutcomeDraft = ""
    try await repository.save(restored)
    let created = try await repository.load()
    #expect(created.newOutcomeDraft.isEmpty)
    #expect(created.outcomes.first?.id == id)
    #expect(created.outcomes.first?.text == "Build the engineering room\nwith preserved whitespace")
    #expect(created.messages.count == 1)
    await #expect(throws: WorkspaceError.staleRevision) { try await repository.save(workspace) }
}

@Test func importedSourceIdentitySurvivesReloadAndPreventsDuplicates() throws {
    var workspace = Workspace()
    let issueID = UUID().uuidString
    let source = OutcomeSource(kind: .linear, id: issueID, url: URL(string: "https://linear.app/team/issue/ENG-1")!)
    _ = try workspace.recordOutcome("Imported engineering ticket", source: source)
    var restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    #expect(restored.outcomes.first?.source == source)
    let duplicate = OutcomeSource(kind: .linear, id: issueID.lowercased(), url: source.url)
    #expect(throws: WorkspaceError.duplicateSource) {
        try restored.recordOutcome("Renamed title does not create a duplicate", source: duplicate)
    }
    #expect(restored == workspace)
    _ = try restored.recordOutcome("Unrelated local outcome with the same title")
    #expect(restored.outcomes.count == 2)
}

@Test func issueReservationsAreStableAndScopedToOutcomeAndTask() throws {
    var workspace = Workspace()
    let first = try workspace.recordOutcome("First publication")
    let second = try workspace.recordOutcome("Second publication")
    let reserved = try workspace.reserveIssuePublication(outcomeID: first, taskID: "interface")
    let repeated = try workspace.reserveIssuePublication(outcomeID: first, taskID: "interface")
    let separate = try workspace.reserveIssuePublication(outcomeID: second, taskID: "interface")
    #expect(reserved == repeated)
    #expect(reserved.id != separate.id && reserved.issueID != separate.issueID)
    #expect(reserved.identifier == nil && reserved.webURL == nil && reserved.publishedTask == nil)
    let unchanged = workspace
    #expect(throws: WorkspaceError.missingOutcome) {
        try workspace.reserveIssuePublication(outcomeID: UUID(), taskID: "interface")
    }
    #expect(workspace == unchanged)
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    #expect(restored.issueBinding(outcomeID: first, taskID: "interface") == reserved)
}

@Test func receiptsMustMatchReservationAndRetainThePublishedSnapshot() throws {
    var workspace = Workspace()
    let outcome = try workspace.recordOutcome("Publish tasks")
    let sent = task("interface", path: "Apps/Original.swift")
    let revised = task("interface", path: "Apps/Revised.swift")
    let receiptURL = URL(string: "https://linear.app/team/issue/ENG-2")!
    #expect(throws: WorkspaceError.missingIssueBinding) {
        try workspace.recordIssuePublication(outcomeID: outcome, task: sent, issueID: UUID(),
                                             identifier: "ENG-2", webURL: receiptURL)
    }
    let reserved = try workspace.reserveIssuePublication(outcomeID: outcome, taskID: sent.id)
    try workspace.attach(WorkPlan(summary: "Revised while publishing", tasks: [revised]), to: outcome)
    let unchanged = workspace
    #expect(throws: WorkspaceError.issueReceiptMismatch) {
        try workspace.recordIssuePublication(outcomeID: outcome, task: sent, issueID: UUID(),
                                             identifier: "ENG-2", webURL: receiptURL)
    }
    #expect(workspace == unchanged)
    try workspace.recordIssuePublication(outcomeID: outcome, task: sent, issueID: reserved.issueID,
                                         identifier: "ENG-2", webURL: receiptURL)
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    let binding = try #require(restored.issueBinding(outcomeID: outcome, taskID: sent.id))
    #expect(binding.publishedTask == sent)
    #expect(binding.identifier == "ENG-2" && binding.webURL == receiptURL)
    #expect(restored.outcomes.first?.plan?.tasks == [revised])
}

@Test func draftAndMessageCommitTogether() async throws {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
    var workspace = Workspace()
    let outcome = try workspace.recordOutcome("Build the room")
    workspace.drafts[outcome] = "Keep this exact text\nincluding whitespace "
    try await repository.save(workspace)
    let restored = try await repository.load()
    #expect(restored.drafts == workspace.drafts)
    try workspace.recordMessage(try #require(workspace.drafts[outcome]), for: outcome)
    workspace.drafts[outcome] = nil
    try await repository.save(workspace)
    try await repository.save(workspace) // Retrying the same commit is idempotent.
    let sent = try await repository.load()
    #expect(sent.drafts.isEmpty)
    #expect(sent.messages.count == 2)
    await #expect(throws: WorkspaceError.staleRevision) { try await repository.save(restored) }
    #expect(try await repository.load() == sent)
}

@Test func rejectsOverlappingApplePaths() {
    for paths in [("Sources/Room.swift", "sources/room.swift"), ("Apps", "Apps/Room.swift"),
                  ("Sources/Caf\u{00e9}.swift", "Sources/Cafe\u{0301}.swift")] {
        #expect(throws: PlanError.self) {
            try PlanValidator.validate(.init(summary: "Build", tasks: [task("a", path: paths.0), task("b", path: paths.1)]))
        }
    }
}

@Test func permitsDisjointFilesAndOrderedHandoffs() throws {
    try PlanValidator.validate(.init(summary: "Build", tasks: [task("a", path: "Sources/A.swift"), task("b", path: "Sources/B.swift")]))
    try PlanValidator.validate(.init(summary: "Build", tasks: [task("a", path: "Sources"), task("b", path: "Sources/A.swift", dependencies: ["a"])]))
}

@Test func validatesTransitiveHandoffs() throws {
    try PlanValidator.validate(.init(summary: "Build", tasks: [task("a", path: "Sources"), task("b", path: "Tests", dependencies: ["a"]), task("c", path: "Sources", dependencies: ["b"])]))
}

@Test func rejectsCyclesUnknownDependenciesAndDuplicateIDs() {
    for tasks in [
        [task("a", path: "A", dependencies: ["b"]), task("b", path: "B", dependencies: ["a"])],
        [task("a", path: "A", dependencies: ["missing"])],
        [task("a", path: "A"), task("a", path: "B")]
    ] { #expect(throws: PlanError.self) { try PlanValidator.validate(.init(summary: "Build", tasks: tasks)) } }
}

@Test func rejectsUnsafePaths() {
    for path in ["../A", "/A", "A/../B", "A//B", "A\\B", "A/*", "A/", "A\nB", "A:stream"] {
        #expect(throws: PlanError.self) { try PlanValidator.validate(.init(summary: "Build", tasks: [task("a", path: path)])) }
    }
}

@Test func incompleteQuestionsStayPending() throws {
    let first = Question(prompt: "Which destination?"), second = Question(prompt: "What budget?")
    var batch = QuestionBatch(outcomeID: UUID(), questions: [first, second])
    try batch.answer([first.id: "Private engineering group"])
    #expect(!batch.isComplete)
    let restored = try JSONDecoder().decode(QuestionBatch.self, from: JSONEncoder().encode(batch))
    #expect(restored.questions[0].answer == "Private engineering group")
    #expect(throws: PlanError.self) { try batch.answer([UUID(): "Unrelated"]) }
    try batch.answer([second.id: "Use existing resources"])
    #expect(batch.isComplete)
}

@Test func availabilityRequiresRecentIdleHeartbeat() {
    let now = Date()
    #expect(Presence(specialty: .models, lastSeen: now, busy: false).isAvailable(at: now))
    #expect(!Presence(specialty: .models, lastSeen: now.addingTimeInterval(-91), busy: false).isAvailable(at: now))
    #expect(!Presence(specialty: .models, lastSeen: now, busy: true).isAvailable(at: now))
    #expect(!Presence(specialty: .models, lastSeen: now.addingTimeInterval(1), busy: false).isAvailable(at: now))
}

@Test func persistsOutcomesAndRejectsStaleWrites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
    var workspace = try await repository.load()
    let old = workspace
    let id = try workspace.recordOutcome("Build the native engineering room")
    try workspace.attach(.init(summary: "Build one screen", tasks: [task("room", path: "Apps/Room.swift")]), to: id)
    try await repository.save(workspace)
    #expect(try await repository.load() == workspace)
    await #expect(throws: WorkspaceError.staleRevision) { try await repository.save(old) }
    var conflicting = workspace; conflicting.messages = []
    await #expect(throws: WorkspaceError.duplicateRevision) { try await repository.save(conflicting) }
}

@Test func corruptWorkspaceIsNeverOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("workspace.json")
    let corrupt = Data("not json".utf8); try corrupt.write(to: url)
    let repository = WorkspaceRepository(url: url)
    await #expect(throws: (any Error).self) { try await repository.save(Workspace()) }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func rejectsFutureSchemaAndEmptyOutcomes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
    var workspace = Workspace()
    #expect(throws: WorkspaceError.emptyOutcome) { try workspace.recordOutcome(" \n ") }
    workspace.version = 99
    await #expect(throws: WorkspaceError.unsupportedVersion(99)) { try await repository.save(workspace) }
}

import Foundation
import Testing
@testable import EngineeringCore

private func task(_ id: String, path: String, dependencies: [String] = []) -> WorkTask {
    .init(id: id, title: "Implement \(id)", owner: .interface, paths: [path],
          acceptance: ["Verify \(id) behavior"], dependencies: dependencies,
          handoff: "Share commit, changed files, test commands and results.")
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

import Foundation
import Testing
@testable import EngineeringCore

@Suite struct ExecutionReceiptJournalTests {
    @Test func publicationReceiptSurvivesRelaunchAndRepeatedSaveIsIdempotent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/publications.json")
        let receipt = fixture()
        let first = ExecutionReceiptJournal(url: url)
        #expect(try await first.load().isEmpty)
        try await first.save(receipt)
        let original = try Data(contentsOf: url)
        try await first.save(receipt)
        #expect(try Data(contentsOf: url) == original)
        let reopened = ExecutionReceiptJournal(url: url)
        #expect(try await reopened.load() == [receipt])
        try await reopened.save(receipt)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func conflictingCommitAndPullRequestCannotReplaceSavedReceipt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("publications.json")
        let receipt = fixture()
        let journal = ExecutionReceiptJournal(url: url)
        try await journal.save(receipt)
        let original = try Data(contentsOf: url)
        let differentCommit = fixture(executionID: receipt.executionID, key: receipt.key,
                                      remoteHeadSHA: String(repeating: "d", count: 40))
        await #expect(throws: ExecutionPublicationError.pullRequestConflict) { try await journal.save(differentCommit) }
        let differentPullRequest = fixture(executionID: receipt.executionID, key: receipt.key, number: 43)
        await #expect(throws: ExecutionPublicationError.pullRequestConflict) { try await journal.save(differentPullRequest) }
        #expect(try Data(contentsOf: url) == original)
        #expect(try await journal.load() == [receipt])
        #expect(try await ExecutionReceiptJournal(url: url).load() == [receipt])
    }

    @Test func foreignRepositoryReceiptIsRejectedWithoutChangingDisk() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("publications.json")
        let receipt = fixture()
        let journal = ExecutionReceiptJournal(url: url)
        try await journal.save(receipt)
        let original = try Data(contentsOf: url)
        let foreign = fixture(url: URL(string: "https://github.com/other/project/pull/42")!)
        await #expect(throws: ExecutionPublicationError.invalidRecord) { try await journal.save(foreign) }
        #expect(try Data(contentsOf: url) == original)
        #expect(try await journal.load() == [receipt])
    }

    @Test func unreadableJournalIsPreservedAndCannotBeOverwrittenBySave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("publications.json")
        let original = Data("[{\"executionID\": unfinished saved receipt".utf8)
        try original.write(to: url)
        let journal = ExecutionReceiptJournal(url: url)
        await #expect(throws: (any Error).self) { _ = try await journal.load() }
        #expect(try Data(contentsOf: url) == original)
        await #expect(throws: (any Error).self) { try await journal.save(fixture()) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func duplicateExecutionIdentityAndInvalidSavedScopeAreRejectedWithoutRepairingFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("publications.json")
        let receipt = fixture()
        let duplicates = try JSONEncoder().encode([receipt, receipt])
        try duplicates.write(to: url)
        await #expect(throws: ExecutionPublicationError.invalidRecord) { _ = try await ExecutionReceiptJournal(url: url).load() }
        #expect(try Data(contentsOf: url) == duplicates)
        let invalidScope = try JSONEncoder().encode([fixture(url: URL(string: "https://github.com/other/project/pull/42")!)])
        try invalidScope.write(to: url)
        await #expect(throws: ExecutionPublicationError.invalidRecord) { _ = try await ExecutionReceiptJournal(url: url).load() }
        #expect(try Data(contentsOf: url) == invalidScope)
    }

    @Test func legacyRuntimeSnapshotWithoutPublicationsDecodesAsEmpty() throws {
        let data = Data(#"{"connected":false,"developers":[],"records":[],"blocker":null}"#.utf8)
        let snapshot = try JSONDecoder().decode(ExecutionSnapshot.self, from: data)
        #expect(!snapshot.connected)
        #expect(snapshot.pullRequests.isEmpty)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(ExecutionSnapshot.self, from: encoded) == snapshot)
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appendingPathComponent("receipt-check-\(UUID().uuidString)", isDirectory: true)
    }

    private func fixture(executionID: UUID = UUID(), key: ExecutionTaskKey = .init(outcomeID: UUID(), taskID: "native-navigation"),
                         number: Int = 42, url: URL? = nil, remoteHeadSHA: String = String(repeating: "a", count: 40)) -> ExecutionPullRequestReceipt {
        .init(executionID: executionID, key: key, pullRequestNumber: number,
              url: url ?? URL(string: "https://github.com/\(ServiceScope.repository)/pull/\(number)")!,
              branch: "engineering/\(executionID.uuidString.lowercased())", baseBranch: "main",
              remoteHeadSHA: remoteHeadSHA, localCommitSHA: String(repeating: "b", count: 40), remoteTreeSHA: String(repeating: "c", count: 40))
    }
}

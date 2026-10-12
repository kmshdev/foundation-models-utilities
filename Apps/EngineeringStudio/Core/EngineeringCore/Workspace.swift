import Foundation

public struct Workspace: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var revision = 0
    public var outcomes: [Outcome] = []
    public var messages: [RoomMessage] = []
    public var questions: [QuestionBatch] = []
    /// Persisted with messages so sending and clearing a composer are atomic.
    public var drafts: [UUID: String] = [:]
    /// Text for the creation sheet before an outcome identity has been allocated.
    public var newOutcomeDraft = ""
    public var issueBindings: [TaskIssueBinding] = []
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, revision, outcomes, messages, questions, drafts, newOutcomeDraft, issueBindings
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        revision = try values.decode(Int.self, forKey: .revision)
        outcomes = try values.decode([Outcome].self, forKey: .outcomes)
        messages = try values.decode([RoomMessage].self, forKey: .messages)
        questions = try values.decode([QuestionBatch].self, forKey: .questions)
        // Workspaces written before draft persistence remain readable.
        drafts = try values.decodeIfPresent([UUID: String].self, forKey: .drafts) ?? [:]
        newOutcomeDraft = try values.decodeIfPresent(String.self, forKey: .newOutcomeDraft) ?? ""
        issueBindings = try values.decodeIfPresent([TaskIssueBinding].self, forKey: .issueBindings) ?? []
    }

    @discardableResult public mutating func recordOutcome(_ input: String, source: OutcomeSource? = nil) throws -> UUID {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WorkspaceError.emptyOutcome }
        if let source, outcomes.contains(where: { $0.source?.matches(kind: source.kind, id: source.id) == true }) {
            throw WorkspaceError.duplicateSource
        }
        let outcome = Outcome(text: text, source: source)
        outcomes.append(outcome)
        messages.append(.init(author: .user, text: text, outcomeID: outcome.id))
        revision += 1
        return outcome.id
    }

    public func issueBinding(outcomeID: UUID, taskID: String) -> TaskIssueBinding? {
        issueBindings.first { $0.outcomeID == outcomeID && $0.taskID == taskID }
    }

    public mutating func reserveIssuePublication(outcomeID: UUID, taskID: String) throws -> TaskIssueBinding {
        guard outcomes.contains(where: { $0.id == outcomeID }) else { throw WorkspaceError.missingOutcome }
        if let existing = issueBinding(outcomeID: outcomeID, taskID: taskID) { return existing }
        let binding = TaskIssueBinding(outcomeID: outcomeID, taskID: taskID)
        issueBindings.append(binding)
        revision += 1
        return binding
    }

    public mutating func recordIssuePublication(outcomeID: UUID, task: WorkTask, issueID: UUID,
                                                identifier: String, webURL: URL) throws {
        guard outcomes.contains(where: { $0.id == outcomeID }) else { throw WorkspaceError.missingOutcome }
        guard let index = issueBindings.firstIndex(where: { $0.outcomeID == outcomeID && $0.taskID == task.id }) else {
            throw WorkspaceError.missingIssueBinding
        }
        guard issueBindings[index].issueID == issueID else { throw WorkspaceError.issueReceiptMismatch }
        // Keep the sent snapshot even if the latest plan changed during network I/O.
        issueBindings[index].record(identifier: identifier, webURL: webURL, task: task)
        revision += 1
    }

    public mutating func attach(_ plan: WorkPlan, to id: UUID) throws {
        try PlanValidator.validate(plan)
        guard let index = outcomes.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.missingOutcome }
        outcomes[index].plan = plan
        messages.append(.init(author: .coordinator, text: plan.summary, outcomeID: id))
        revision += 1
    }

    public mutating func recordMessage(_ input: String, for outcomeID: UUID) throws {
        guard outcomes.contains(where: { $0.id == outcomeID }) else { throw WorkspaceError.missingOutcome }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WorkspaceError.emptyMessage }
        messages.append(.init(author: .user, text: text, outcomeID: outcomeID))
        revision += 1
    }
}

import Foundation

public enum Specialty: String, CaseIterable, Codable, Sendable, Identifiable {
    case architecture, models, authentication, interface, platforms, cloud, quality, integration
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .architecture: "Architecture & concurrency"
        case .models: "Foundation Models"
        case .authentication: "Authentication & security"
        case .interface: "SwiftUI & accessibility"
        case .platforms: "iOS & macOS"
        case .cloud: "Cloudflare infrastructure"
        case .quality: "Testing & evaluation"
        case .integration: "CI & integration"
        }
    }
    public var symbol: String {
        switch self {
        case .architecture: "square.stack.3d.up"
        case .models: "brain"
        case .authentication: "key"
        case .interface: "rectangle.3.group"
        case .platforms: "laptopcomputer.and.iphone"
        case .cloud: "cloud"
        case .quality: "checkmark.seal"
        case .integration: "arrow.triangle.branch"
        }
    }
}

public struct OutcomeSource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case linear }
    public let kind: Kind
    public let id: String
    public let url: URL

    public init(kind: Kind, id: String, url: URL) {
        self.kind = kind; self.id = id; self.url = url
    }

    public func matches(kind: Kind, id: String) -> Bool {
        guard self.kind == kind else { return false }
        if let first = UUID(uuidString: self.id), let second = UUID(uuidString: id) { return first == second }
        return self.id == id
    }
}

public struct Outcome: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public var plan: WorkPlan?
    public let source: OutcomeSource?
    public init(id: UUID = UUID(), text: String, createdAt: Date = .now, plan: WorkPlan? = nil,
                source: OutcomeSource? = nil) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.plan = plan; self.source = source
    }
}

public struct WorkTask: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let owner: Specialty
    public let paths: [String]
    public let acceptance: [String]
    public let dependencies: [String]
    public let handoff: String
    public init(id: String, title: String, owner: Specialty, paths: [String], acceptance: [String], dependencies: [String], handoff: String) {
        self.id = id; self.title = title; self.owner = owner; self.paths = paths
        self.acceptance = acceptance; self.dependencies = dependencies; self.handoff = handoff
    }
}

public struct WorkPlan: Codable, Sendable, Equatable {
    public let summary: String
    public let tasks: [WorkTask]
    public init(summary: String, tasks: [WorkTask]) { self.summary = summary; self.tasks = tasks }
}

/// A durable, client-reserved Linear issue ID for one task within one outcome.
/// A reservation is not evidence that Linear accepted a mutation.
public struct TaskIssueBinding: Identifiable, Codable, Sendable, Equatable {
    public let outcomeID: UUID
    public let taskID: String
    public let issueID: UUID
    public private(set) var identifier: String?
    public private(set) var webURL: URL?
    public private(set) var publishedTask: WorkTask?
    public var id: String { "\(outcomeID.uuidString)/\(taskID)" }

    public init(outcomeID: UUID, taskID: String, issueID: UUID = UUID()) {
        self.outcomeID = outcomeID; self.taskID = taskID; self.issueID = issueID
    }

    fileprivate mutating func record(identifier: String, webURL: URL, task: WorkTask) {
        self.identifier = identifier; self.webURL = webURL; publishedTask = task
    }
}

public struct RoomMessage: Identifiable, Codable, Sendable, Equatable {
    public enum Author: String, Codable, Sendable { case user, coordinator }
    public let id: UUID
    public let author: Author
    public let text: String
    public let createdAt: Date
    /// Optional for compatibility with workspaces written before outcome threads.
    public let outcomeID: UUID?
    public init(id: UUID = UUID(), author: Author, text: String, createdAt: Date = .now, outcomeID: UUID? = nil) {
        self.id = id; self.author = author; self.text = text; self.createdAt = createdAt
        self.outcomeID = outcomeID
    }
}

/// The app never infers availability from a role existing in its configuration.
public struct Presence: Sendable {
    public let specialty: Specialty
    public let lastSeen: Date
    public let busy: Bool
    public init(specialty: Specialty, lastSeen: Date, busy: Bool) {
        self.specialty = specialty; self.lastSeen = lastSeen; self.busy = busy
    }
    public func isAvailable(at date: Date, maximumAge: TimeInterval = 90) -> Bool {
        let age = date.timeIntervalSince(lastSeen)
        return !busy && age >= 0 && age <= maximumAge
    }
}

public struct Workspace: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var revision = 0
    public var outcomes: [Outcome] = []
    public var messages: [RoomMessage] = []
    public var questions: [QuestionBatch] = []
    /// Persisted with messages so sending and clearing a composer are atomic.
    public var drafts: [UUID: String] = [:]
    public var issueBindings: [TaskIssueBinding] = []
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, revision, outcomes, messages, questions, drafts, issueBindings
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

public enum WorkspaceError: Error, LocalizedError, Equatable {
    case emptyOutcome, emptyMessage, missingOutcome, unsupportedVersion(Int), staleRevision, duplicateRevision
    case duplicateSource, missingIssueBinding, issueReceiptMismatch, workspaceNotLoaded, publicationNotSaved
    public var errorDescription: String? {
        switch self {
        case .emptyOutcome: "Describe an outcome before adding it."
        case .emptyMessage: "Write a message before sending it."
        case .missingOutcome: "The outcome could not be found."
        case .unsupportedVersion(let version): "This workspace uses version \(version). Update the app to open it."
        case .staleRevision: "A newer workspace is already saved. Reload before saving."
        case .duplicateRevision: "Conflicting changes have the same revision. Reload before saving."
        case .duplicateSource: "This issue has already been imported."
        case .missingIssueBinding: "Reserve and save an issue ID before publishing this task."
        case .issueReceiptMismatch: "The Linear receipt does not match this task's reserved issue ID."
        case .workspaceNotLoaded: "Open the workspace before publishing tasks."
        case .publicationNotSaved: "Could not save the workspace publication state on this device. Retry before continuing."
        }
    }
}

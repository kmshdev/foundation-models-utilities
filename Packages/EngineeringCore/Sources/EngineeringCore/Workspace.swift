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

public struct Outcome: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public var plan: WorkPlan?
    public init(id: UUID = UUID(), text: String, createdAt: Date = .now, plan: WorkPlan? = nil) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.plan = plan
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

public struct RoomMessage: Identifiable, Codable, Sendable, Equatable {
    public enum Author: String, Codable, Sendable { case user, coordinator }
    public let id: UUID
    public let author: Author
    public let text: String
    public let createdAt: Date
    public init(id: UUID = UUID(), author: Author, text: String, createdAt: Date = .now) {
        self.id = id; self.author = author; self.text = text; self.createdAt = createdAt
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
    public init() {}

    @discardableResult public mutating func recordOutcome(_ input: String) throws -> UUID {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WorkspaceError.emptyOutcome }
        let outcome = Outcome(text: text)
        outcomes.append(outcome)
        messages.append(.init(author: .user, text: text))
        revision += 1
        return outcome.id
    }

    public mutating func attach(_ plan: WorkPlan, to id: UUID) throws {
        try PlanValidator.validate(plan)
        guard let index = outcomes.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.missingOutcome }
        outcomes[index].plan = plan
        messages.append(.init(author: .coordinator, text: plan.summary))
        revision += 1
    }
}

public enum WorkspaceError: Error, LocalizedError, Equatable {
    case emptyOutcome, missingOutcome, unsupportedVersion(Int), staleRevision, duplicateRevision
    public var errorDescription: String? {
        switch self {
        case .emptyOutcome: "Describe an outcome before adding it."
        case .missingOutcome: "The outcome could not be found."
        case .unsupportedVersion(let version): "This workspace uses version \(version). Update the app to open it."
        case .staleRevision: "A newer workspace is already saved. Reload before saving."
        case .duplicateRevision: "Conflicting changes have the same revision. Reload before saving."
        }
    }
}

import Foundation

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

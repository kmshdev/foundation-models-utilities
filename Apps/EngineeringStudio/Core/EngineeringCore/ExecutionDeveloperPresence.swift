import Foundation

public struct ExecutionDeveloperPresence: Codable, Sendable, Equatable, Identifiable {
    public let specialty: Specialty
    public let threadID: String
    public let observedAt: Date
    public let activeTask: ExecutionTaskKey?
    public var id: String { specialty.id }

    public init(specialty: Specialty, threadID: String, observedAt: Date, activeTask: ExecutionTaskKey?) {
        self.specialty = specialty
        self.threadID = threadID
        self.observedAt = observedAt
        self.activeTask = activeTask
    }

    public func isAvailable(at date: Date, maximumAge: TimeInterval = 90) -> Bool {
        let age = date.timeIntervalSince(observedAt)
        return activeTask == nil && age >= 0 && age <= maximumAge
    }
}

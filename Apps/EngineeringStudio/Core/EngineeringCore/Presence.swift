import Foundation

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

import Foundation

/// The worker's bounded acceptance attestation. Git and command evidence are
/// independently collected by the coordinator, rather than trusted from JSON.
public struct ExecutionTaskResult: Codable, Sendable, Equatable {
    public enum Disposition: String, Codable, Sendable { case completed, blocked }
    public let disposition: Disposition
    public let summary: String
    public let acceptedCriteria: [String]
    public let blocker: String
    public init(disposition: Disposition, summary: String, acceptedCriteria: [String], blocker: String) {
        self.disposition = disposition; self.summary = summary; self.acceptedCriteria = acceptedCriteria; self.blocker = blocker
    }

    package static let schema: ExecutionJSON = .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array(["disposition", "summary", "acceptedCriteria", "blocker"].map(ExecutionJSON.string)),
        "properties": .object([
            "disposition": .object(["type": .string("string"), "enum": .array([.string("completed"), .string("blocked")])]),
            "summary": .object(["type": .string("string")]),
            "acceptedCriteria": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            "blocker": .object(["type": .string("string")])])])
}

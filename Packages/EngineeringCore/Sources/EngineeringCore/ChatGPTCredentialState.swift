import Foundation

/// Protected data: never store in workspace documents or diagnostics.
public struct ChatGPTCredentialState: Codable, Sendable {
    public let hostID: String
    public var registrations: [ChatGPTRegistration]
    public var activeClientID: String?
    /// Issued registration awaiting a validated identity; never displayed as an authenticated account.
    public var pendingClientID: String?

    public init(hostID: String, registrations: [ChatGPTRegistration] = [], activeClientID: String? = nil) {
        self.hostID = hostID
        self.registrations = registrations
        self.activeClientID = activeClientID
        self.pendingClientID = nil
    }
}

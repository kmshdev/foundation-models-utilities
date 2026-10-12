import Foundation

/// Display metadata. Email never identifies or combines registrations.
public struct ChatGPTAccount: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let subject: String
    public let email: String?
    public let displayName: String?
    public let planUsageEnabled: Bool
    public let isSignedIn: Bool
}

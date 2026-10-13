import Foundation

public struct ChatGPTRegistration: Codable, Sendable {
    public let clientID: String
    public let subject: String
    public let issuer: String
    public let email: String?
    public let displayName: String?
    public var tokens: ChatGPTTokenSet?
    public var pendingRefresh: ChatGPTPendingRefresh?

    package var account: ChatGPTAccount {
        ChatGPTAccount(id: clientID, subject: subject, email: email, displayName: displayName,
                       planUsageEnabled: tokens?.scopes.contains("chatgpt.tokens.use.direct") == true,
                       isSignedIn: tokens != nil)
    }

    package init(clientID: String, subject: String, issuer: String, email: String?, displayName: String?, tokens: ChatGPTTokenSet?) {
        self.clientID = clientID
        self.subject = subject
        self.issuer = issuer
        self.email = email
        self.displayName = displayName
        self.tokens = tokens
        self.pendingRefresh = nil
    }
}

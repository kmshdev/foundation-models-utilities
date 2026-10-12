/// The scene observes identity changes without exposing provider credentials.
public struct StudioPlanningIdentity: Equatable, Sendable {
    public let accountID: String?
    public let model: String?
    public let isSignedIn: Bool

    package init(accountID: String?, model: String?, isSignedIn: Bool) {
        self.accountID = accountID; self.model = model; self.isSignedIn = isSignedIn
    }
}

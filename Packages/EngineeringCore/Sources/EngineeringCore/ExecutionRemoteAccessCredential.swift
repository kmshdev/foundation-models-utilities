/// Cloudflare Access credentials authorize the tunnel; the separate pairing token authorizes the executor.
public struct ExecutionRemoteAccessCredential: Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) throws {
        guard Self.valid(clientID), Self.valid(clientSecret) else { throw ExecutionRemoteError.invalidConfiguration }
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}

/// Supplies app-owned subscription credentials without exposing storage to model clients.
public protocol ChatGPTTokenProviding: Sendable {
    func accessToken() async throws -> String
}

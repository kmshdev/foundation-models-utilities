import Foundation

public struct ExecutionNotification: Sendable, Equatable {
    public let method: String
    public let params: ExecutionJSON
    public init(method: String, params: ExecutionJSON = .object([:])) { self.method = method; self.params = params }
}

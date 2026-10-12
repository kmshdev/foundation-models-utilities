import Foundation

public struct ChatGPTResponsesHTTPStream: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: AsyncThrowingStream<Data, any Error>
    public let cancel: @Sendable () -> Void

    public init(statusCode: Int, headers: [String: String] = [:], body: AsyncThrowingStream<Data, any Error>,
                cancel: @escaping @Sendable () -> Void = {}) {
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
        self.body = body
        self.cancel = cancel
    }
}

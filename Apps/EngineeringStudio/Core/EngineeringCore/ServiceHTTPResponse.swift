import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ServiceHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }
}

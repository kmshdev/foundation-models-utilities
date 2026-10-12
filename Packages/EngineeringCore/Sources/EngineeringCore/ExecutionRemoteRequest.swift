import Foundation

/// Strict single-request HTTP/1.1 framing. No chunking, request pipelines, query credentials or proxy targets.
public struct ExecutionRemoteRequest: Sendable {
    public let method: String
    public let path: String
    public let authorization: String?
    public let body: Data

    public static func parse(_ bytes: Data) throws -> Self? {
        guard bytes.count <= ExecutionRemoteLimits.maximumHeaderBytes + ExecutionRemoteLimits.maximumBodyBytes else {
            throw ExecutionRemoteError.oversizedRequest
        }
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            if bytes.count > ExecutionRemoteLimits.maximumHeaderBytes { throw ExecutionRemoteError.oversizedRequest }
            return nil
        }
        guard boundary.upperBound <= ExecutionRemoteLimits.maximumHeaderBytes else { throw ExecutionRemoteError.oversizedRequest }
        guard let header = String(data: bytes[..<boundary.lowerBound], encoding: .utf8),
              header.utf8.allSatisfy({ $0 == 13 || $0 == 10 || (32...126).contains($0) }) else {
            throw ExecutionRemoteError.malformedRequest
        }
        let lines = header.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1", parts[0] == "GET" || parts[0] == "POST" else {
            throw ExecutionRemoteError.malformedRequest
        }
        let method = String(parts[0]), path = String(parts[1])
        let allowed: Set<String> = ["/v1/execution/snapshot", "/v1/execution/dispatch", "/v1/execution/cancel", "/v1/execution/resume", "/v1/execution/stop", "/v1/execution/restart", "/v1/execution/publish"]
        guard allowed.contains(path) else { throw ExecutionRemoteError.unsupportedRoute }
        guard (path == "/v1/execution/snapshot") == (method == "GET") else { throw ExecutionRemoteError.unsupportedRoute }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { throw ExecutionRemoteError.malformedRequest }
            let name = String(line[..<colon]).lowercased()
            guard name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  headers[name] == nil else { throw ExecutionRemoteError.malformedRequest }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"]?.isEmpty == false, headers["transfer-encoding"] == nil,
              headers["expect"] == nil else { throw ExecutionRemoteError.malformedRequest }
        let length: Int
        if let text = headers["content-length"] {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text) else {
                throw ExecutionRemoteError.malformedRequest
            }
            length = value
        } else {
            guard method == "GET" else { throw ExecutionRemoteError.malformedRequest }
            length = 0
        }
        guard length <= ExecutionRemoteLimits.maximumBodyBytes else { throw ExecutionRemoteError.oversizedRequest }
        guard method != "GET" || length == 0 else { throw ExecutionRemoteError.malformedRequest }
        let emptyOperation = path == "/v1/execution/stop" || path == "/v1/execution/restart"
        if method == "POST", !emptyOperation {
            guard headers["content-type"]?.lowercased() == "application/json", length > 0 else { throw ExecutionRemoteError.malformedRequest }
        }
        if emptyOperation, length != 0 { throw ExecutionRemoteError.malformedRequest }
        let available = bytes.count - boundary.upperBound
        guard available <= length else { throw ExecutionRemoteError.malformedRequest }
        guard available == length else { return nil }
        return Self(method: method, path: path, authorization: headers["authorization"], body: Data(bytes[boundary.upperBound...]))
    }

    /// Constant-time comparison over the configured token length. Tokens are never included in errors.
    public func isAuthorized(pairingToken: String) -> Bool {
        guard ExecutionRemoteLimits.validPairingToken(pairingToken), let authorization else { return false }
        let expected = Array("Bearer \(pairingToken)".utf8), actual = Array(authorization.utf8)
        var difference = actual.count ^ expected.count
        for index in expected.indices { difference |= Int(expected[index] ^ (index < actual.count ? actual[index] : 0)) }
        return difference == 0
    }
}

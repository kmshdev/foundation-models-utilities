import Foundation

/// Only the bound IPv4 loopback port and the pending Linear callback are accepted.
public enum ProviderOAuthLoopbackRequest {
    public static let path = "/oauth/linear/callback"

    public static func callbackURL(header: Data, port: UInt16, expectedState: String) throws -> URL {
        guard port != 0, header.count <= 16_384,
              let text = String(data: header, encoding: .utf8), text.hasSuffix("\r\n\r\n"),
              text.unicodeScalars.allSatisfy({ $0.value == 13 || $0.value == 10 || (32...126).contains($0.value) }) else {
            throw ProviderOAuthError.invalidCallback
        }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.count <= 66 else { throw ProviderOAuthError.invalidCallback }
        let request = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0",
              request[1].hasPrefix("\(path)?"), !request[1].contains("#"),
              let url = URL(string: "http://127.0.0.1:\(port)\(request[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == path else { throw ProviderOAuthError.invalidCallback }
        let fields = lines.dropFirst().filter { !$0.isEmpty }
        guard fields.allSatisfy({ line in
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return false }
            return line[..<colon].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { throw ProviderOAuthError.invalidCallback }
        let hosts = fields.filter { $0.lowercased().hasPrefix("host:") }
        let lengths = fields.filter { $0.lowercased().hasPrefix("content-length:") }
        guard hosts.count == 1, hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)",
              !fields.contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") }),
              lengths.count <= 1,
              lengths.isEmpty || lengths[0].dropFirst(15).trimmingCharacters(in: .whitespaces) == "0" else {
            throw ProviderOAuthError.invalidCallback
        }
        let items = components.queryItems ?? []
        guard !expectedState.isEmpty, Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw ProviderOAuthError.invalidCallback
        }
        return url
    }
}

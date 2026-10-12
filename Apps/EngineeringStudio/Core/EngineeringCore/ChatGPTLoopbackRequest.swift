import Foundation

/// Bounded parsing of an HTTP/1 callback. URLs and headers never become remote endpoints.
public struct ChatGPTLoopbackRequest: Sendable {
    public static func callbackURL(header: Data, port: UInt16, expectedState: String) throws -> URL {
        guard header.count <= 16_384, let text = String(data: header, encoding: .utf8), text.hasSuffix("\r\n\r\n") else { throw ChatGPTAuthenticationError.invalidCallback }
        let lines = text.components(separatedBy: "\r\n")
        let request = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0",
              request[1].hasPrefix("/auth/callback?"), !request[1].contains("#"),
              let url = URL(string: "http://127.0.0.1:\(port)\(request[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.path == "/auth/callback" else { throw ChatGPTAuthenticationError.invalidCallback }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1, hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)" else { throw ChatGPTAuthenticationError.invalidCallback }
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.first(where: { $0.name == "state" })?.value == expectedState else { throw ChatGPTAuthenticationError.stateMismatch }
        return url
    }
}

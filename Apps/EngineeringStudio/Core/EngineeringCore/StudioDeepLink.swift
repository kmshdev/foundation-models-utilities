import Foundation

/// A bounded navigation intent. Opening it never creates work or dispatches tasks.
public struct StudioDeepLink: Sendable, Equatable {
    public let outcomeID: UUID
    public let taskID: String?

    /// Accepts only engineeringstudio://outcome/<UUID> with an optional task ID.
    public init?(url: URL) {
        guard url.baseURL == nil, url.absoluteString.utf8.count <= 2_048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "engineeringstudio",
              components.host?.lowercased() == "outcome",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil,
              components.path.utf8.count == 37, components.path.hasPrefix("/"),
              components.percentEncodedPath == components.path,
              let outcomeID = UUID(uuidString: String(components.path.dropFirst())) else { return nil }

        let query = components.queryItems ?? []
        guard query.count <= 1, query.allSatisfy({ $0.name == "task" }) else { return nil }
        let taskID: String?
        if let item = query.first {
            guard let value = item.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf8.count <= 256,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            taskID = value
        } else { taskID = nil }
        self.outcomeID = outcomeID
        self.taskID = taskID
    }

    public static func parse(_ url: URL) -> Self? { Self(url: url) }
}

import Foundation

/// Serializes writes and refuses to replace a newer snapshot with an older one.
/// A failed/corrupt read is reported, never converted to an empty workspace.
public actor WorkspaceRepository {
    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        guard workspace.version == Workspace.currentVersion else {
            throw WorkspaceError.unsupportedVersion(workspace.version)
        }
        return workspace
    }

    public func save(_ workspace: Workspace) throws {
        guard workspace.version == Workspace.currentVersion else {
            throw WorkspaceError.unsupportedVersion(workspace.version)
        }
        let previous = try load()
        guard workspace.revision >= previous.revision else { throw WorkspaceError.staleRevision }
        if workspace.revision == previous.revision && workspace != previous {
            throw WorkspaceError.duplicateRevision
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(workspace).write(to: url, options: .atomic)
    }
}

#if os(macOS)
import EngineeringCore
import Foundation

/// App Sandbox permits execution in the app container, not an arbitrary picked path.
/// Copy the explicitly selected standalone CLI into an app-owned location before launch.
enum RuntimeExecutableInstaller {
    @concurrent static func install(_ selected: URL, directory: URL) async throws -> URL {
        let attributes = try selected.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true,
              let size = attributes.fileSize, (1...536_870_912).contains(size),
              FileManager.default.isExecutableFile(atPath: selected.path) else {
            throw ExecutionError.invalidConfiguration("Choose the standalone executable Codex binary, rather than a shell wrapper or folder.")
        }
        let handle = try FileHandle(forReadingFrom: selected)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4)
        let supportedMagic = [Data([0xcf, 0xfa, 0xed, 0xfe]), Data([0xfe, 0xed, 0xfa, 0xcf]),
                              Data([0xca, 0xfe, 0xba, 0xbe]), Data([0xca, 0xfe, 0xba, 0xbf])]
        guard let magic, supportedMagic.contains(magic) else {
            throw ExecutionError.invalidConfiguration("Choose Codex's native Mac executable. Shell and Node wrappers cannot run this Swift app's developer runtime.")
        }
        let destinationDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let executable = destinationDirectory.appendingPathComponent("codex")
        do {
            try FileManager.default.copyItem(at: selected, to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            return executable
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectory)
            throw error
        }
    }
}
#endif

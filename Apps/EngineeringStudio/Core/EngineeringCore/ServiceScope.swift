import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The app's approved service boundary. Credentials never select an endpoint or repository.
public enum ServiceScope {
    public static let repository = "kmshdev/foundation-models-utilities"
    public static let linearProjectID = "c655b4e0-e003-424a-a29a-3674e9a3983b"
    public static let linearTeamID = "1294bebc-4432-4532-8618-baa5794bdaec"
}

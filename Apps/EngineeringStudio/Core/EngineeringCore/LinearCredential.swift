import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LinearCredential: Sendable {
    case personalAPIKey(String)
    case oauthToken(String)
}

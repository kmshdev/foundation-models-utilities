import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ServiceValidation {
    static func checked(_ response: ServiceHTTPResponse) throws -> ServiceHTTPResponse {
        guard (200..<300).contains(response.statusCode) else {
            throw ServiceClientError.http(status: response.statusCode, retryAfter: response.headers["retry-after"])
        }
        return response
    }

    static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do { return try JSONDecoder().decode(Value.self, from: data) }
        catch { throw ServiceClientError.invalidResponse }
    }

    static func validateCredential(_ value: String) throws {
        guard !value.isEmpty else { throw ServiceClientError.missingCredential }
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map({ $0 < 32 || $0 == 127 }) == true }) else {
            throw ServiceClientError.invalidInput("credential")
        }
    }

    static func validateTitle(_ title: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 255 else {
            throw ServiceClientError.invalidInput("title")
        }
    }

    static func validateBranch(_ branch: String) throws {
        let invalidCharacters = CharacterSet(charactersIn: " ~^:?*[\\").union(.controlCharacters)
        guard !branch.isEmpty, branch != "@", !branch.hasPrefix("/"), !branch.hasSuffix("/"), !branch.hasSuffix("."),
              !branch.contains(".."), !branch.contains("@{"), !branch.contains("//"),
              branch.rangeOfCharacter(from: invalidCharacters) == nil,
              branch.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }) else {
            throw ServiceClientError.invalidInput("branch")
        }
    }

    static func validateIssueIdentifier(_ id: String) throws {
        guard UUID(uuidString: id) != nil || id.range(of: "^[A-Za-z][A-Za-z0-9]*-[0-9]+$", options: .regularExpression) != nil else {
            throw ServiceClientError.invalidInput("issue identifier")
        }
    }
}

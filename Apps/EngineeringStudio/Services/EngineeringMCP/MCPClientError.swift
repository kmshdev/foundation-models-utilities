import Foundation

public enum MCPClientError: Error, Equatable, Sendable {
    case invalidAccount
    case invalidLimits
    case invalidOperationName
    case duplicateReviewedOperation(String)
    case notInitialized
    case connectionClosed
    case operationInProgress
    case toolsUnavailable
    case unsupportedProtocol(String)
    case catalogPageLimit
    case catalogToolLimit
    case repeatedCursor
    case duplicateTool(String)
    case catalogChanged
    case operationNotReviewed(String)
    case mutationsDisabled(String)
    case toolUnavailable(String)
    case schemaChanged(String)
    case argumentsTooLarge
    case responseTooLarge
    case deadlineExceeded
}

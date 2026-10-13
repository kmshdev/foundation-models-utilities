import Foundation

public enum WorkspaceError: Error, LocalizedError, Equatable {
    case emptyOutcome, emptyMessage, missingOutcome, unsupportedVersion(Int), staleRevision, duplicateRevision
    case duplicateSource, missingIssueBinding, issueReceiptMismatch, workspaceNotLoaded, publicationNotSaved
    public var errorDescription: String? {
        switch self {
        case .emptyOutcome: "Describe an outcome before adding it."
        case .emptyMessage: "Write a message before sending it."
        case .missingOutcome: "The outcome could not be found."
        case .unsupportedVersion(let version): "This workspace uses version \(version). Update the app to open it."
        case .staleRevision: "A newer workspace is already saved. Reload before saving."
        case .duplicateRevision: "Conflicting changes have the same revision. Reload before saving."
        case .duplicateSource: "This issue has already been imported."
        case .missingIssueBinding: "Reserve and save an issue ID before publishing this task."
        case .issueReceiptMismatch: "The Linear receipt does not match this task's reserved issue ID."
        case .workspaceNotLoaded: "Open the workspace before publishing tasks."
        case .publicationNotSaved: "Could not save the workspace publication state on this device. Retry before continuing."
        }
    }
}

import Foundation

public enum ExecutionPublicationError: Error, LocalizedError, Sendable, Equatable {
    case invalidRecord, invalidGitObject, unsupportedHistory, unsupportedFileMode(String), tooLarge
    case missingParent(String), branchConflict, pullRequestConflict, closedPullRequest, ambiguousMutation(String), alreadyPublishing
    case githubWriteDenied(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidRecord: "Only a completed execution with verified files, acceptance criteria and an actual commit can publish a draft pull request."
        case .invalidGitObject: "The immutable Git objects do not match this execution's saved scope or commit receipt."
        case .unsupportedHistory: "This task's commit is not a single child of its saved worktree base. Review and consolidate its local history before publication."
        case .unsupportedFileMode(let mode): "Git file mode \(mode) needs a separately reviewed publication path. Regular and executable files are supported."
        case .tooLarge: "The task exceeds the bounded publication size. Split its file scope before publishing."
        case .missingParent(let sha): "The task's base \(sha.prefix(12)) has no verified GitHub publication. Publish its dependency first or provide a verified integration base."
        case .branchConflict: "The execution branch has unrelated GitHub changes. They were not overwritten. Inspect the branch before continuing."
        case .pullRequestConflict: "An existing pull request does not match this execution's branch, base, draft state or commit. It was not changed or duplicated."
        case .closedPullRequest: "This execution already has a closed pull request. It was not reopened or duplicated."
        case .ambiguousMutation(let action): "GitHub may have saved \(action), but reconciliation did not confirm it. Retry publication to check the existing branch and pull request."
        case .alreadyPublishing: "This execution is already publishing its draft pull request."
        case .githubWriteDenied(let status):
            "GitHub rejected this write (HTTP \(status)). Update the app's GitHub connection with Contents and Pull requests: Read and write for \(ServiceScope.repository). Workflow changes additionally need Workflows: write; repository branch rules can also reject writes. No Actions secret is needed."
        }
    }
}

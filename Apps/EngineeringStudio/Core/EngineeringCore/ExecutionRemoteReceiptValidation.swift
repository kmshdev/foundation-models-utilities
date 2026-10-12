import Foundation

package enum ExecutionRemoteReceiptValidation {
    package static func matches(_ receipt: ExecutionPullRequestReceipt, key: ExecutionTaskKey) -> Bool {
        guard receipt.key == key, receipt.pullRequestNumber > 0,
              let url = URLComponents(url: receipt.url, resolvingAgainstBaseURL: false),
              url.scheme == "https", url.host == "github.com", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/\(ServiceScope.repository)/pull/\(receipt.pullRequestNumber)",
              !receipt.branch.isEmpty, !receipt.baseBranch.isEmpty else { return false }
        return [receipt.remoteHeadSHA, receipt.localCommitSHA, receipt.remoteTreeSHA].allSatisfy {
            ($0.utf8.count == 40 || $0.utf8.count == 64) && $0.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
            }
        }
    }
}

# Evidence and next work

Recorded 2026-10-11. This is a checkpoint, not a production-readiness claim.

## Verified

- Both full production targets and the real FoundationPlanner built on Xcode 27 / Swift 6.4: [run 38155972610](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38155972610).
- Durable per-outcome composer drafts, backward-compatible workspace decoding, ordered saves and send/retry behavior are implemented. Fourteen portable core tests passed at `946807d`; actual store regression checks passed in [preview run 38156253905](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38156253905).
- Both production targets built again at `946807d`. The actual Mac app launched and its [capture](../Documentation/NativeBuild/macos-27.png) was retained. That run was subsequently canceled during the iOS simulator diagnostic, so it is not an overall passing run.
- SDK availability is resolved. Normal validation builds both apps; native launch capture is an optional bounded diagnostic.
- At `7b54a8d`, follow-up planning queues automatically, coalesces new context and rejects stale results. Task reopening, legacy conversation visibility, selected-answer accessibility and new-outcome sheet protection were corrected. [Both production builds and 14 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254209), plus [SDK 27 preview/store checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254245), passed. Updated native preview captures are in `Documentation/Previews`.

## Remaining product work

1. Connect supported personal ChatGPT subscription access through a documented integration. Preserve separation between authentication and platform build hosts; do not substitute paid API access or an invented authentication bridge.
2. Connect developer execution to the implemented GitHub/Linear clients, including observed presence, exclusive task ownership, durable context handoff and verified test/PR receipts. Scoped Linear intake and task publication, repository PR/run reads, and Keychain credential settings are now implemented. Native validation of this change is being recorded below; service connection is not proof of developer execution.
3. Complete end-to-end native interactions, accessibility and iOS runtime validation. The iOS 27 simulator booted but its install/launch diagnostic stalled; a successful iOS build does not prove runtime behavior.
4. Complete accessibility-setting and device coverage. Updated SDK 27 native previews cover normal/narrow windows, empty workspace, light mode and increased contrast; the narrow capture confirms the sidebar connection label remains readable. Static captures do not prove assistive-technology interaction.
5. Perform signing, device distribution and operational validation when those enter the authorized delivery scope.

These items are future implementation work; installing development roles, skills and strategy does not itself complete them. Use the runbook matching the next user outcome, not the entire backlog at once.

## Repository branch

Resolved 2026-10-12: the user renamed the app branch from `swift-app` to `main` and made it the default. The local checkout now tracks `origin/main`, preserves the prior utilities-only local branch as `archived-utilities-main`, and includes the user's SDK 27 skills and harness commits. Native validation and capture workflows now watch `main`. No administration credential is needed to continue this app work.

## Service integration checkpoint

- GitHub and Linear connectors successfully read the approved repository, Engineering Workflow Automation project, and existing ENG-46 issue. No additional user setup information was needed for implementation.
- Swift clients implement fixed-scope repository/PR/workflow/check reads, draft PR creation, project/issue reads and issue writes. Native connection settings use Keychain. Imported issue identity survives relaunch. Task publication persists a reserved UUID before network mutation and reconciles lost responses without creating duplicate tickets.
- A live, unauthenticated read using the actual Swift GitHubService and URLSession transport succeeded: configured repository, open PRs, 47 workflow runs, and exact-commit check lookup. Zero checks for the documentation-only commit was reported as zero, not interpreted as test success. No live test issues or PRs were created.
- The official direct personal ChatGPT protocol is documented in [ChatGPT access](../Documentation/Engineering/ChatGPT-access.md). Mac and Node authentication dependencies were incorrect assumptions; direct Swift implementation is supported by the language-neutral protocol. Sign-in itself remains implementation work.
- At `629824a`, [both production builds and all 32 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176451777) passed. The [native preview run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176451776) also passed actual StudioStore and ServiceConnections regressions, with five native captures. Public GitHub reads were additionally exercised live; Linear mutations used deterministic receipts, not throwaway production tickets.
- At `a9bf51d`, publication additionally stops remaining outdated writes when assignments change. Recovered remote content must match before the current task snapshot is marked published. [Both production builds and 32 core tests passed again](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176836232); [native store/service checks and three publication race scenarios passed](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176836230). Updated captures are saved in `Documentation/Previews`.

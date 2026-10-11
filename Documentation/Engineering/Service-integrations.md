# GitHub and Linear connections

Implemented in Swift using Foundation URLSession, Codable, Observation and Security Keychain. No service proxy or alternate language runtime is required.

## Verified scope

- Repository: `kmshdev/foundation-models-utilities`, repository ID `1409524201`.
- Linear project: [Engineering Workflow Automation](https://linear.app/kmsh-dev/project/engineering-workflow-automation-93f936d49f78), ID `c655b4e0-e003-424a-a29a-3674e9a3983b`.
- Linear team: Engineering (`ENG`), ID `1294bebc-4432-4532-8618-baa5794bdaec`.
- Existing implementation issue: [ENG-46](https://linear.app/kmsh-dev/issue/ENG-46/build-the-native-swiftui-engineering-coordinator-and-connect-eight).

These resources were read successfully through the current session's connectors on 2026-10-11. Connector authorization is separate from credentials in an installed app. Tokens are never extracted from the connector or included in source, screenshots, workspace files or logs.

## App behavior

The app loads public repository metadata, open pull requests and workflow runs without credentials. Connections accepts an optional GitHub token and a Linear personal API key. A successful repository/project request precedes Keychain replacement. A failed replacement leaves the previous credential intact. Native secure fields clear after successful connection. Device-only Keychain accessibility requires the device to be unlocked.

Project issues can become local outcomes. Their source identity and URL persist; importing again after relaunch does not duplicate the outcome. The existing planning queue handles imported context. The app does not mark imported issues complete or infer a developer's availability.

Publishing a plan reserves a UUID for each outcome/task and flushes it to disk before any mutation. Linear's documented `IssueCreateInput.id` accepts this UUID. Each successful receipt is persisted before proceeding to the next task. If a create response is lost, lookup and reconciliation use the same UUID; retries never reserve a replacement. If lookup is inconclusive, publication pauses. Known issues are updated after project/team verification. Receipts include the exact task snapshot, so a changed plan is visibly out of sync until published again. There is no atomic multi-issue transaction; partial progress is retained and retryable. Linear does not expose an atomic project-scope precondition for issue updates, so the client validates scope both before the mutation and in its receipt.

GitHub check results are tied to a requested commit SHA. Workflow conclusions are displayed as repository evidence; they are not converted into invented test counts or task acceptance. A Swift draft-PR method exists for the execution integration; the current UI displays real PR links rather than fabricating a PR from a plan.

## Transport and failures

Endpoints and repository/project scope are fixed in `ServiceScope`. Requests use ephemeral sessions, bounded timeouts and pagination; redirects are refused to prevent credential forwarding. Pagination never follows an arbitrary server-provided URL. A truncated result is labeled. Failed refreshes retain last-known results with a stale-state label. Disconnect clears credential-backed cached data. GraphQL errors reject partial data, including HTTP 200 responses. Error messages omit response bodies and credentials. Mutations are not blindly retried.

The portable test suite covers request contracts, pagination, authorization, GraphQL partial failures, scope mismatches and ambiguous writes. The native preview harness runs the actual connection model and StudioStore with injected HTTP/credential fixtures: verification before saving, credential-store failure, stale refreshes, lost create responses, repeated publication, disk failure before network mutation and disconnect cleanup. These checks do not establish production account sign-in on a user's device or live developer execution.

## Primary references

- [GitHub REST API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions)
- [GitHub pull requests](https://docs.github.com/en/rest/pulls/pulls)
- [GitHub workflow runs](https://docs.github.com/en/rest/actions/workflow-runs)
- [GitHub check runs](https://docs.github.com/en/rest/checks/runs)
- [Linear GraphQL overview and authentication](https://linear.app/developers/graphql)
- [Linear pagination](https://linear.app/developers/pagination)
- [Linear official schema, including caller-provided issue UUID](https://github.com/linear/linear/blob/master/packages/sdk/src/schema.graphql)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)

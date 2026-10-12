# Engineering Studio

A native SwiftUI workspace for a personal engineering coordinator and eight specialist developers. Swift 6.4, iOS 27, and macOS 27.

**Status: both native app targets build with Xcode 27 and Swift 6.4; not yet a connected, deployable bot team.** [Toolchain evidence](../../Documentation/Engineering/Toolchain.md). There is no TestFlight or signed/notarized distribution build yet.

## Open the app

Open `EngineeringStudio.xcodeproj` in Xcode with the iOS 27/macOS 27 SDKs and Swift 6.4. Select `EngineeringStudioiOS` or `EngineeringStudioMac`, choose a simulator or Mac destination, and run. A physical device requires your signing team. On-device planning additionally requires an Apple Intelligence capable device with its model available.

The app starts with an empty, local workspace. Use New Outcome to begin. Outcomes and conversation history persist in Application Support. All eight specialties are honestly shown as offline until developer execution is connected.

## Workspace design

The accepted design uses three native panes: outcomes, the selected outcome's conversation/tasks, and the selected task's details. Mac uses `HSplitView` to keep the resizable sidebar and task panel inset below the unified toolbar. iPhone uses `NavigationSplitView` for compact navigation. Task details occupy the third pane rather than a modal overlay. The Mac sidebar uses native selection and supports Cmd-Control-S visibility toggling. New Outcome and Developers use system sheets. Settings uses the standard Mac Settings scene and a sheet on iOS.

The window follows system light/dark appearance, with a continuous neutral background, semantic standard materials for content and composer, the native unified toolbar, and Liquid Glass for actions. Blue identifies Send, green identifies planning/run actions, and amber identifies cancellation/pause intent. Symbols and labels carry meaning alongside color. Run, pause, restart, cancel and resume control the connected runtime. A planned task never claims to be running or tested; command exits and developer-reported acceptance appear separately.

Unsent conversation and new-outcome drafts are saved after a short typing pause and restored across relaunch. Closing the creation sheet retains its draft. Accepted outcome/message creation and its draft clearing share one atomic disk snapshot. Pending writes flush on scene inactivity; normal Mac quit waits for a successful flush and leaves the app open if saving fails. Force termination can still interrupt a pending debounce. Messages sent from an outcome are attached to that outcome and supplied as context when preparing its next plan. Legacy messages without an outcome ID remain accessible under All Outcomes, without guessing which thread they belong to. Search finds outcomes. Incoming messages follow the conversation while you are reading its latest content; if you scroll back, a New messages action lets you return without interrupting your reading. Explicit scroll animation respects Reduce Motion. Task selection is cleared when its outcome changes or a replacement plan removes that task. The inspector is keyed by outcome and task, so action feedback cannot carry into another outcome. Earlier execution receipts are grouped as Previous executions whenever they do not match the current assignment.

The Swift-only preview host in `Tests/NativePreviewHost` imports the production Swift modules. Screenshot fixtures do not open account browsers or reach external services. Its regression checks exercise the actual Foundation Models framework with deterministic transport, native cryptography and isolated Keychain records, the loopback listener, service publication and runtime lifecycle. Its screenshots are native UI with fixture data. The separate Xcode validation builds both complete application targets; native previews do not prove live bot execution. See the [SwiftUI review](../../Documentation/Design/SwiftUI-review.md) for coverage and release blockers.

You may explicitly enable optional on-device planning in Settings. It uses `LanguageModelSession.DynamicProfile`, the `LanguageModel` protocol, guided generation, typed error handling, and the utilities package's rolling history window. Model tool calling is disabled for this planning-only session. A generated plan is validated before it is saved. Any genuinely blocking questions appear together in the Engineering conversation; partial answers persist and planning waits for all answers in that batch.

With on-device planning enabled, sending a follow-up automatically queues an updated plan. Work is serialized across outcomes; repeated follow-ups coalesce with the latest context, and outdated results are discarded. Other outcomes show when their planning is queued. Cancel Planning and disabling the model clear queued requests and prevent late results from publishing. Complete answers resume planning automatically; incomplete answers continue to block only their own outcome.

Plan details show ownership, file scopes, acceptance criteria, dependencies, and required handoff context. A saved plan is not a dispatched task, passed test, or created pull request.

## GitHub and Linear

Open Connections from the workspace menu or Settings. The configured public GitHub repository loads without a token, including open pull requests and recent workflow runs with commit links. Optional account credentials and the Linear personal key are entered in native secure fields and saved in this device's Keychain after scope verification; they never enter workspace JSON.

Linear is scoped to Engineering Workflow Automation. Use an issue as an outcome to preserve its source link and start the normal planning flow. Imports remain deduplicated after relaunch. Publish a visible plan to create one Linear issue per task, including specialty, file scope, acceptance criteria, dependencies and handoff. The app saves a reserved issue UUID before sending; retries recover the same issue and retain confirmed receipts. Re-publishing updates those issues. A Linear ticket is not proof that a developer has started executing it.

See [service behavior and failure handling](../../Documentation/Engineering/Service-integrations.md). Connections in this chat do not transfer account tokens into a separately installed app.

The [provider-adapter proposal](../../Documentation/Engineering/Provider-adapters.md) describes system-browser OAuth, provider passkeys, GitHub App registration and Linear MCP dynamic registration. `EngineeringMCP` provides the pinned official Swift SDK transport with reviewed read-only operations and deterministic contract tests. Browser-login controls and workflow-controlled MCP context collection remain proposed; the current Connections UI continues to use its existing credential flow.

## Repository structure

```
EngineeringStudio.xcodeproj/    iOS and macOS application targets and shared schemes
Apps/EngineeringStudio/
  App/                        Scenes, deep-links, dependency wiring and assets
  Features/                   Workspace, Settings, Integration and Runtime APIs/views
  Workflows/                  Planning, publication, dispatch and lifecycle orchestration
  Services/                   GitHub/Linear, MCP, authentication/model/runtime services
  Core/                       Leaf contracts, persistence/networking and native UI primitives
    FoundationModelsUtilities/  Existing utilities library; root package product retained
  Tests/                      Portable/MCP tests and native regression/capture host
Package.swift                 FoundationModelsUtilities package manifest
Tests/                        FoundationModelsUtilities library tests
.github/workflows/            Swift 6.4 tests and Apple-platform build/capture checks
```

The app lives in [`kmshdev/foundation-models-utilities`](https://github.com/kmshdev/foundation-models-utilities), whose default branch is `main`. The layered migration is reviewed in [draft PR #2](https://github.com/kmshdev/foundation-models-utilities/pull/2). Both application targets consume the local app package; StudioServices obtains FoundationModelsUtilities from the root package using an explicit local package name. No self-referencing remote checkout is needed. The [module map](../../Documentation/Engineering/Module-architecture.md) explains dependency direction and migration order. Run the commands below from the repository root.

Implementation code in this project is Swift. Use Apple frameworks, Swift packages and documented Apple APIs. Do not introduce TypeScript, JavaScript, Python, Node-based services or a web UI into this project. Cloud preferences do not override the Swift requirement.

## Validation

Run the portable core tests with Swift 6.4:

```sh
swift test --package-path Apps/EngineeringStudio --jobs 2
```

Build the native targets on a compatible Mac:

```sh
xcodebuild -project EngineeringStudio.xcodeproj -scheme EngineeringStudioiOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EngineeringStudio.xcodeproj -scheme EngineeringStudioMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Portable tests cover Apple-style path collisions, unsafe paths, overlapping scope, ordered and cyclic handoffs, partial question batches, heartbeat freshness, disk round trips, stale writes, schema errors, corrupt-file preservation and deep-link parsing. MCP fixtures cover negotiation, bounded catalogs/results, reviewed schemas and arguments, structured receipts, errors, timeout and cancellation. Linux tests do not establish SwiftUI correctness, Apple streaming/OAuth or real model behavior. CI fails explicitly when the required Apple SDK/compiler is unavailable; it does not silently lower the target platform.

## ChatGPT and developer execution

Open Settings → ChatGPT accounts and models. The native sign-in uses the documented direct OAuth/PKCE protocol and loopback callback. Registrations and rotating tokens stay in Keychain; model names come from the account's actual catalog. Select a model and enable ChatGPT planning. The Responses stream is adapted to Foundation Models `LanguageModel`, so the planning profile and guided schema use the real framework. On-device planning remains a separate option.

Open Developer Runtime to execute a plan. On Mac, choose the approved utilities clone and Codex's standalone native executable. The app copies that explicitly selected executable into its container because App Sandbox does not permit executing arbitrary user-picked locations. Scope bookmarks retain access to the selected clone. The runtime uses an app-owned isolated Codex home and the documented subscription provider, excluding its OAuth token from developer shell commands. Account/model changes await local executor shutdown; changing the phone's own account does not stop an independent shared host.

The coordinator starts eight specialist conversations, obtains presence from the actual app server, atomically reserves task identities and creates disjoint worktrees. Dependency descendants receive confirmed ancestor commits, commands, result summaries and required handoff context. Changed files are checked against owned paths before a task can produce a completed commit receipt. A lost delivery is retained as interrupted and resumed through its saved conversation; it is never blindly delivered again. Status, blocked work, developer-reported acceptance and observed command exits/output appear in task details.

Newly prepared plans dispatch automatically while a runtime is connected. Restored plans do not dispatch on launch. Run Team dispatches an existing visible plan. Pause Team stops active developers and retains context. The workspace then exposes Restart Team; individual interrupted tasks can resume afterward. Connect Team opens setup when no runtime exists. Team controls are independent of planning cancellation, serialize repeated actions and reject stale availability replies. Only observed availability is displayed.

A host with a scoped GitHub credential publishes fresh completed tasks as draft PRs. It reads the immutable saved commit rather than the current checkout, verifies Git objects and paths, creates a stable branch through GitHub's Git Data API, and reconciles ambiguous responses before considering another write. Durable receipts retain local and remote SHA separately. A matching published ancestor becomes a stacked PR base. Composite unpublished dependency bases and unrelated branch changes block publication with an explicit reason. Create Draft PR allows retrying a retained result. This path never merges changes.

For iPhone control, enable runtime sharing on the host. The Swift Network server binds only `127.0.0.1:16080`; Cloudflare Tunnel routes an HTTPS hostname to that loopback origin. Pair the iPhone with the generated code, optionally using a Cloudflare Access service token. Remote credentials stay in the phone's Keychain; the host owns model and GitHub credentials. The bridge supports availability, dispatch, cancel, resume, pause, restart and draft PR publication. [Runtime setup](../../Documentation/Engineering/Developer-runtime.md) explains the precise operational requirements.

## Remaining validation and delivery

Live personal-account browser consent, subscription inference and end-to-end developer turns still require signing into the installed app. A passing injected transport test does not establish account entitlement. Actual on-device iPhone loopback/browser foreground behavior remains to be exercised with that sign-in. Multimodal inputs and signed device distribution remain additional product scope. Cloudflare's account is connected in this chat; creating a usable route additionally requires an active execution host, rather than a repository secret.

The eight roles and priority order preserve the requested setup: architecture/concurrency; Foundation Models; authentication/security; SwiftUI/accessibility; iOS/macOS; Cloudflare; testing/evaluation; CI/integration. Priority is explicit user order, urgent defects, dependency blockers, then Linear priority. Routine approval gates are not reintroduced.

# Engineering Studio

A native SwiftUI workspace for a personal engineering coordinator and eight specialist developers. Swift 6.4, iOS 27, and macOS 27.

**Status: native app source and tested coordination core; not yet a connected, deployable bot team.** The Apple-platform build must pass before this is treated as a runnable app. There is no TestFlight or signed Mac build yet.

## Open the app

Open `EngineeringStudio.xcodeproj` in Xcode with the iOS 27/macOS 27 SDKs and Swift 6.4. Select `EngineeringStudioiOS` or `EngineeringStudioMac`, choose a simulator or Mac destination, and run. A physical device requires your signing team. On-device planning additionally requires an Apple Intelligence capable device with its model available.

The app starts with an empty, local workspace. Use New Outcome to begin. Outcomes and conversation history persist in Application Support. All eight specialties are honestly shown as offline until developer execution is connected.

## Workspace design

The accepted design uses three native `NavigationSplitView` columns: outcomes, the selected outcome's conversation/tasks, and the selected task's details. Columns resize on Mac and adapt to compact navigation on iPhone. Task details occupy the third column rather than a modal overlay. New Outcome, Developers and Settings use system sheets.

The dark window uses a continuous background, semantic standard materials for content, the native unified toolbar, and Liquid Glass for the composer and actions. Blue identifies Send, green identifies planning/run actions, and amber identifies cancellation/pause intent. Symbols and labels carry meaning alongside color. Execution and verification actions remain disabled with explanations until their services exist; a planned task never claims to be running or tested.

Messages sent from an outcome are attached to that outcome and supplied as context when preparing its next plan. Legacy messages without an outcome ID remain accessible under All Outcomes, without guessing which thread they belong to. Search finds outcomes. Task selection is cleared when its outcome changes or a replacement plan removes that task.

The Swift-only preview host in `Tools/SwiftUIPreview` compiles the real views and store using a disabled model service. Its screenshots are native UI with fixture data, not evidence of live bot execution. It also typechecks shared UI against the installed iOS simulator SDK; production SDK 27 validation is separate.

You may explicitly enable optional on-device planning in Settings. It uses `LanguageModelSession.DynamicProfile`, the `LanguageModel` protocol, guided generation, typed error handling, and the utilities package's rolling history window. Model tool calling is disabled for this planning-only session. A generated plan is validated before it is saved. Any genuinely blocking questions appear together in the Engineering conversation; partial answers persist and planning waits for all answers in that batch.

Plan details show ownership, file scopes, acceptance criteria, dependencies, and required handoff context. A saved plan is not a dispatched task, passed test, or created pull request.

## Repository structure

```
EngineeringStudio.xcodeproj/    iOS and macOS application targets and shared schemes
Apps/EngineeringStudio/        Native app, feature views, state and model integration
Packages/EngineeringCore/      Swift domain types, validation, persistence and tests
Sources/                      FoundationModelsUtilities library
Tests/                        FoundationModelsUtilities tests
.github/workflows/            Core tests and Apple-platform build checks
```

The app lives on the `swift-app` branch of [`kmshdev/foundation-models-utilities`](https://github.com/kmshdev/foundation-models-utilities/tree/swift-app). Both app targets consume FoundationModelsUtilities directly from the root Swift package and EngineeringCore from `Packages/EngineeringCore`. No self-referencing remote package checkout is needed. Run the commands below from the repository root. The earlier TypeScript coordinator PR remains closed and is not part of this branch.

Implementation code in this project is Swift. Use Apple frameworks, Swift packages and documented Apple APIs. Do not introduce TypeScript, JavaScript, Python, Node-based services or a web UI into this project. Cloud preferences do not override the Swift requirement.

## Validation

Run the portable core tests with Swift 6.4:

```sh
swift test --package-path Packages/EngineeringCore
```

Build the native targets on a compatible Mac:

```sh
xcodebuild -project EngineeringStudio.xcodeproj -scheme EngineeringStudioiOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EngineeringStudio.xcodeproj -scheme EngineeringStudioMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The core tests cover Apple-style path collisions, unsafe paths, overlapping scope, ordered and cyclic handoffs, partial question batches, heartbeat freshness, disk round trips, stale writes, schema errors, and corrupt-file preservation. They do not establish SwiftUI correctness or real model behavior. CI fails explicitly when the required Apple SDK/compiler is unavailable; it does not silently lower the target platform.

## Remaining product work

- Supported personal ChatGPT subscription sign-in and model transport. The app has no fabricated login flow, no API-key substitute for a subscription, and no Mac-runner authentication requirement.
- GitHub and Linear authentication, scope enforcement, repository/project discovery, synchronization and deep links to actual work.
- Swift-based coordination and connected developer execution, with real heartbeats and durable task ownership. Research documented hosting options compatible with Swift before selecting cloud infrastructure.
- Verified commit/artifact transfers, test evidence tied to acceptance criteria, pull requests, blockers and live progress.
- Multimodal inputs, accessibility and layout validation on actual iOS/macOS, UI tests, signing and distribution.

The eight roles and priority order preserve the requested setup: architecture/concurrency; Foundation Models; authentication/security; SwiftUI/accessibility; iOS/macOS; Cloudflare; testing/evaluation; CI/integration. Priority is explicit user order, urgent defects, dependency blockers, then Linear priority. Routine approval gates are not reintroduced. This initial app does not perform external actions.

# Engineering Studio

The default `main` branch contains the native engineering app and the FoundationModelsUtilities library in one repository.

- All application, coordinator, model integration and developer execution implementation code must be Swift. Use Swift 6.4, SwiftUI, iOS 27 and macOS 27. Do not introduce TypeScript, JavaScript, Python, a Node runtime or a web app. Project metadata, asset catalogs and CI configuration are not alternate implementation stacks.
- Research current Apple documentation, tutorials, sample projects and relevant Swift repositories before choosing APIs or adding dependencies. Verify API availability and distinguish documented capabilities from assumptions.
- Keep native app source in `Apps/EngineeringStudio`, portable coordination code in `Packages/EngineeringCore`, and the existing FoundationModelsUtilities library in `Sources`. Both application targets consume the root library as a local Swift package.
- Prefer Apple frameworks and Swift packages. Cloudflare is a hosting preference only when compatible with the Swift implementation requirement; research the supported developer path rather than adding a non-Swift service.
- Preserve the eight confirmed specialties and priority order. Batch genuinely blocking questions, retain answers, and wait before dependent work. Do not reintroduce removed routine approval checkpoints.
- Never claim developers are available without actual presence, that a plan was dispatched without delivery, or that a test/PR exists without evidence. Personal ChatGPT subscription access must use a documented, supported integration; an API key is not a subscription and authentication must not be coupled to a Mac runner.
- Validate portable logic with `swift test --package-path Packages/EngineeringCore`. Validate application targets with Xcode and the required Apple SDKs. Linux core tests and syntax checks do not establish a runnable native app.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- If the project uses Localizable.xcstrings, prefer to add user-facing strings using symbol keys (e.g. helloWorld) in the string catalog with `extractionState` set to "manual", accessing them via generated symbols such as  `Text(.helloWorld)`. Offer to translate new keys into all languages supported by the project.


## Development team

- Follow `strategy/README.md` and choose the smallest relevant team from `.codex/agents`. The 24 development profiles are separate from the app's eight specialist bots. Check actual runtime capacity before spawning; eight is a ceiling, not a target. Model and reasoning settings inherit the parent.
- Assign one active writer per file. Record acceptance criteria, dependencies and owned paths before delegation; serialize shared project, store and contract edits. Use the handoff template in `strategy/coordination/handoff-templates.md` before dependent work.
- Installed skills and the Interfaces plugin are aids, not a new authority. User directions and this repository's Swift-only requirements take precedence over generic web examples, questionnaire gates and default publishing or issue-reporting behavior. Never execute installation-time hooks or public reporting automatically.
- Prefer an existing answer and a reasonable implementation choice to another question. If information is genuinely blocking, batch related questions using available in-chat controls and wait for answers before dependent work; continue independent work meanwhile. Do not use an inaccessible HTML artifact to collect answers.
- Use `strategy/runbooks.json` to select a workflow. Keep progress grounded in commits, actual commands, native captures and service receipts. Distinguish build success, app launch and complete product behavior.

## Leverage skills

Use the available swift/swiftui plugins and skills for stronger SwiftUI conventions baked into the app:

- Use swiftui specialsit skill for Authoritative SwiftUI best practices and performance guidance from Apple and always adopt what's new in swiftui SDK 27.
- Foundation model skills for working with LLMs via the [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels), such as custom skills, context management helpers, and a chat completions client that connects to a hosted model of your choice.

- SwiftUI Pro is a broad SwiftUI review skill for modern APIs, maintainability, accessibility, and performance.

- Liquid Glass expert helps adopt the new iOS 26 Liquid Glass APIs and tune custom components so they fit the latest system design.

- SwiftUI performance helps when a feature feels slow or a SwiftUI view update path looks suspicious. It scans for common SwiftUI mistakes and produces a prioritized report of what to fix and where the biggest gains are.

- Swift concurrency expert helps when cryptic errors and compiler warnings start fighting the change you want to make. 

SwiftUI view refactor helps keep files smaller and make SwiftUI code more consistent across the repo.

SwiftUI patterns helps reach for predictable @Observable and @Environment architecture patterns as the app grows.

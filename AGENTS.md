# Engineering Studio

The `swift-app` branch contains the native engineering app and the FoundationModelsUtilities library in one repository.

- All application, coordinator, model integration and developer execution implementation code must be Swift. Use Swift 6.4, SwiftUI, iOS 27 and macOS 27. Do not introduce TypeScript, JavaScript, Python, a Node runtime or a web app. Project metadata, asset catalogs and CI configuration are not alternate implementation stacks.
- Research current Apple documentation, tutorials, sample projects and relevant Swift repositories before choosing APIs or adding dependencies. Verify API availability and distinguish documented capabilities from assumptions.
- Keep native app source in `Apps/EngineeringStudio`, portable coordination code in `Packages/EngineeringCore`, and the existing FoundationModelsUtilities library in `Sources`. Both application targets consume the root library as a local Swift package.
- Prefer Apple frameworks and Swift packages. Cloudflare is a hosting preference only when compatible with the Swift implementation requirement; research the supported developer path rather than adding a non-Swift service.
- Preserve the eight confirmed specialties and priority order. Batch genuinely blocking questions, retain answers, and wait before dependent work. Do not reintroduce removed routine approval checkpoints.
- Never claim developers are available without actual presence, that a plan was dispatched without delivery, or that a test/PR exists without evidence. Personal ChatGPT subscription access must use a documented, supported integration; an API key is not a subscription and authentication must not be coupled to a Mac runner.
- Validate portable logic with `swift test --package-path Packages/EngineeringCore`. Validate application targets with Xcode and the required Apple SDKs. Linux core tests and syntax checks do not establish a runnable native app.

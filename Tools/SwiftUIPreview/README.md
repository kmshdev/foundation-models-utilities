# Native screenshot previews

This Swift-only host compiles the app's actual module graph using Xcode 27 / Swift 6.4 on the `xcode-27` runner. It verifies both SDK versions before compiling. It captures the real window with macOS `screencapture`, including composited AppKit controls that a view bitmap cache omits.

The `EngineeringPreviewHost` executable target lives in `Apps/EngineeringStudio/Tests/NativePreviewHost`. It imports the same Core, Services, Workflows and Features modules as the application. Regression checks use the real Foundation Models framework with deterministic injected transports, native cryptography, isolated Keychain records and local runtime fixtures. Screenshot state is in-memory preview data and never signs in or dispatches developers. Every image is visibly labeled as a preview with services disabled.

`BuildPreview.swift` builds that target through SwiftPM, then creates a disposable app bundle with the production asset catalog. Build products are ignored by Git. Preview checks do not establish production app launch, live-provider consent or a signed distribution build. The separate validation workflow builds both complete application targets.

On macOS 27 with Xcode 27 selected, from the repository root:

```
swift Tools/SwiftUIPreview/BuildPreview.swift
.preview-build/SwiftUIPreview.app/Contents/MacOS/SwiftUIPreview /tmp/native-previews
```

The `Capture native SwiftUI previews` GitHub Actions workflow uploads the PNG captures as a downloadable artifact.

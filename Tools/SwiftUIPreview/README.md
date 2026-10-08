# Native screenshot previews

This Swift-only host compiles the app's actual view and store source on the available macOS 26 runner. It captures the real window with macOS `screencapture`, including composited AppKit controls that a view bitmap cache omits. It does not redraw the UI in HTML or generate an imagined image.

The SDK 27 Foundation Models service is excluded and replaced by a preview-only implementation that always throws if called. State is in-memory preview data. Every image is visibly labeled as a preview with services disabled. These captures do not establish that the full iOS/macOS 27 app builds or runs.

Production targets, package manifests and deployment settings remain unchanged. Build products are disposable and ignored by Git. `BuildPreview.swift` compiles core sources directly for the preview host; it does not change the Swift 6.4 package manifest.

On macOS 26 or later, from the repository root:

```
swift Tools/SwiftUIPreview/BuildPreview.swift
.preview-build/SwiftUIPreview.app/Contents/MacOS/SwiftUIPreview /tmp/native-previews
```

The `Capture native SwiftUI previews` GitHub Actions workflow uploads the PNG captures as a downloadable artifact.

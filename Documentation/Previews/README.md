# Native SwiftUI preview captures

Captured from the real shared SwiftUI views at `99ddde0`, with Xcode 27 / Swift 6.4 and deterministic workspace data. These are fixture previews, not a connected developer team. The [capture and regression run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38188916037) passed.

The subsequent [final source regression run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38189784128) also passed at `b79f343`; its non-UI Git-environment fix does not change these layouts.

The host compiles the actual Foundation Models utilities and adapter, typechecks both app scene branches, and runs native store, service, guided planning, authentication, remote listener and runtime connection checks. Screenshot fixtures do not open browsers, sign into personal accounts or dispatch developer work. [Production app launches](../NativeBuild/README.md) are verified separately.

- [Normal dark workspace](01-workspace.png)
- [Narrow window](02-compact-workspace.png)
- [Empty workspace](03-empty-workspace.png)
- [Increased contrast](04-increased-contrast.png)
- [Light appearance](05-light-workspace.png)

![Native shared workspace with fixture data](01-workspace.png)

Controls use Liquid Glass and SF Symbols. Content and composer use semantic standard materials; task details occupy the third pane. A planned fixture remains Planned, with unavailable execution controls disabled. Static captures validate rendered layout, not VoiceOver behavior or live service results.

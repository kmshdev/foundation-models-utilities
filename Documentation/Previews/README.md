# Native SwiftUI preview captures

Captured from the real shared SwiftUI views at `e64b613`, with Xcode 27 / Swift 6.4 and deterministic workspace data. These are fixture previews, not a connected developer team. The [capture and regression run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38192295529) passed.

The native regressions cover durable new-outcome creation, late catalog replacement, stale runtime snapshots/delivery, serialized Pause/Restart and failed-read retention. Both app scene branches and the actual Foundation Models adapter compile against SDK 27.

The host compiles the actual Foundation Models utilities and adapter, typechecks both app scene branches, and runs native store, service, guided planning, authentication, remote listener and runtime connection checks. Screenshot fixtures do not open browsers, sign into personal accounts or dispatch developer work. [Production app launches](../NativeBuild/README.md) are verified separately.

- [Normal dark workspace](01-workspace.png)
- [Narrow window](02-compact-workspace.png)
- [Empty workspace](03-empty-workspace.png)
- [Increased contrast](04-increased-contrast.png)
- [Light appearance](05-light-workspace.png)
- [Wide workspace](06-wide-workspace.png) — 1600-point content width, bounded conversation/composer.
- [Accessibility layout](07-accessibility-workspace.png) — accessibility2 trait, stacked message metadata and task rows.

![Native shared workspace with fixture data](01-workspace.png)

Controls use Liquid Glass and SF Symbols. Content and composer use semantic standard materials; task details occupy the third pane. A planned fixture remains Planned. Connect Team and Choose Planning Model lead to native setup instead of leaving only disabled execution actions. Static captures validate rendered layout, not VoiceOver behavior or live service results. The Mac accessibility trait capture does not establish iPhone text scaling or touch interaction.

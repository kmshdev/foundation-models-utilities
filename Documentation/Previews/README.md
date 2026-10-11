# Native SwiftUI screen captures

Captured from the actual SwiftUI views at `7b54a8d` using Xcode 27 / Swift 6.4, with isolated preview data and services disabled. These are foreground native windows, not generated mockups. Reduce Transparency was off. Normal captures use regular legibility; the accessibility capture uses an increased-contrast NSAppearance and bold legibility. Production inherits the user's display settings.

[Native capture, SDK 27 scene/view typechecks and store regression checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254245) passed. The isolated host uses a disabled model service; deterministic planner checks use an injected provider. [Both full production builds and 14 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254209) passed separately. Neither result establishes live service integration, iOS runtime interaction or signed distribution. See [design QA](../../design-qa.md) and the [SwiftUI review](../Design/SwiftUI-review.md) for exact scope and blockers.

## Selected outcome and task — 1280 × 910 pixels

![Native engineering workspace](01-workspace.png)

## Narrower Mac window — 1100 × 810 pixels

![Compact native workspace](02-compact-workspace.png)

## Empty workspace — 1280 × 872 pixels

![Empty native workspace](03-empty-workspace.png)

## Increased contrast — 1280 × 910 pixels

![Increased contrast native workspace](04-increased-contrast.png)

## Light appearance — 1280 × 910 pixels

![Light native workspace](05-light-workspace.png)

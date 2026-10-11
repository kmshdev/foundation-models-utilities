# Native SwiftUI screen captures

Captured from the actual SwiftUI views at `a9bf51d` using Xcode 27 / Swift 6.4, with isolated preview data and services disabled. These are foreground native windows, not generated mockups. Reduce Transparency was off. Normal captures use regular legibility; the accessibility capture uses an increased-contrast NSAppearance and bold legibility. Production inherits the user's display settings.

[Native capture, SDK 27 scene/view typechecks and store/service regression checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176836230) passed. The isolated host uses a disabled model service; deterministic planner and connection checks use injected providers. These checks include stale-plan publication, lost-response recovery and older remote content at a reserved issue ID. [Both full production builds and 32 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38176836232) passed separately. Neither result establishes real developer execution, iOS runtime interaction or signed distribution. See the [service evidence](../Engineering/Service-integrations.md) and [SwiftUI review](../Design/SwiftUI-review.md) for exact scope.

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

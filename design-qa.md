# Native workspace QA — SwiftUI review

**Final result: blocked for production acceptance.** Source review and native preview checks are complete. Full SDK 27 app, native interaction and service validation remain outstanding.

The reference supplies the three-pane composition, continuous window, floating controls and SF Symbol scale. This refinement uses neutral system appearance, standard content materials and functional accent color. It does not claim pixel-identical reproduction of the generated blue/glowing illustration. [Review and design rules](Documentation/Design/SwiftUI-review.md) record all requested SwiftUI topics and the product architecture.

## Evidence

The actual native view captures in [Documentation/Previews](Documentation/Previews/README.md) show populated, narrow, empty, increased-contrast and light appearances. Source and implementation were opened and inspected at native resolution, including the same 1280 × 910 window dimensions used in the reference-scale comparison. The original concept is 1487 × 1058 and was treated at equivalent display scale, not as a larger logical viewport.

Observed after refinement:

- The sidebar, conversation and task details retain a common bottom baseline and continuous toolbar background.
- At 1280 pixels, Task / Owner / Status remain separate. At 1100 pixels the conversation uses stacked task metadata without losing ownership or state labels.
- Long source paths wrap in the task pane; the complete path remains available rather than a shortened suffix.
- Dark and light captures retain readable content and selected rows. The reduced-transparency-on case is not captured.
- Empty workspace has a clear New Outcome action. Offline developers, planned assignments, unrun tests and nonexistent PRs are explicitly represented.
- Composer has one standard material backing and a native glass Send button. The inactive Pause action uses disabled styling. Overflow no longer applies a glass modifier over a glass button style.

## Functional checks

The native preview host executes state regression checks against the real `StudioStore`: per-outcome draft identity and isolation, retained edits, successful-send clearing, rejected-send retention, correct message ownership, disk saving and retry after a corrupt-file load. The existing Swift 6.4 core suite has 12 tests covering coordination and persistence.

Both app scene branches and shared views are typechecked with the installed SDK 26 toolchain. The screenshot host replaces FoundationPlanner with a disabled service. This is deliberately separate from the complete Swift 6.4 / SDK 27 app build, which fails the toolchain availability check on the current runner.

## Remaining acceptance work

- SDK 27 build and target-device runs, including the actual model service and package integration.
- Supported personal ChatGPT model transport, GitHub/Linear authentication and synchronization, developer execution and verified test/PR handoffs.
- Keyboard traversal, VoiceOver, live divider resizing, sheets, iPhone compact navigation, accessibility text sizes and Reduce Transparency on native targets.
- Draft persistence across relaunch, pending-write/quit behavior, large-history profiling, signing and distribution.

No screenshot or passing portable test is presented as proof of these missing capabilities. The [earlier reference-correction history](Documentation/Design/reference-correction-history.md) is retained separately.

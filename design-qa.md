# Native workspace QA — SwiftUI review

**Final result: blocked for production acceptance.** Source review and native preview checks are complete. Full SDK 27 builds now pass; native interaction and service acceptance remain outstanding. See [toolchain evidence](Documentation/Engineering/Toolchain.md).

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

The native preview host executes state regression checks against the real `StudioStore`: per-outcome draft identity and isolation, retained edits, successful-send clearing, rejected-send retention, correct message ownership, disk saving and retry after a corrupt-file load. The existing Swift 6.4 core suite has 14 tests covering coordination and persistence.

The preview pipeline now requires Xcode 27 / Swift 6.4 and typechecks both app scene branches and shared views against SDK 27. The screenshot host replaces FoundationPlanner with a disabled service. Full production builds compile the actual model service separately. Earlier stored captures retain their original SDK 26 provenance.

At `7b54a8d`, [native builds and core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254209) and [SDK 27 preview/store checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38158254245) passed. The checked-in captures now come from that SDK 27 run. Automatic planning regression checks verify latest-context coalescing, obsolete-result rejection, queue serialization, cancellation, error recovery and unanswered-question gating. Narrow-window connection text remains legible. Compact re-selection, sheet dismissal protection and VoiceOver choice traits have source/build validation; direct native interaction remains outstanding.

## Remaining acceptance work

- Target-device interaction and model execution checks; the full SDK 27 targets and actual model service now compile.
- Supported personal ChatGPT model transport, GitHub/Linear authentication and synchronization, developer execution and verified test/PR handoffs.
- Keyboard traversal, VoiceOver, live divider resizing, sheets, iPhone compact navigation, accessibility text sizes and Reduce Transparency on native targets.
- Native lifecycle interaction, large-history profiling, signing and distribution. Draft persistence, ordered writes and atomic send/clear now have regression coverage; Mac quit waits for its pending flush.

No screenshot or passing portable test is presented as proof of these missing capabilities. The [earlier reference-correction history](Documentation/Design/reference-correction-history.md) is retained separately.

# Native workspace visual QA — reference correction

**final result: blocked**

The reference correction is implemented and captured. The earlier pass was materially different from the approved concept; those differences were not merely an inactive-window issue. The revised composition is substantially closer, but final product acceptance still needs the complete SDK 27 app and device interaction/material checks described below.

## Source and evidence

- Source: `Documentation/Design/approved-workspace-concept.png` (1487 × 1058 generated concept); the user's displayed reference is approximately 1280 × 910.
- Implementation: `Documentation/Previews/01-workspace.png` (1280 × 910 native pixels, 1280 × 858 content points plus native toolbar, 1× capture).
- Additional captures: `02-compact-workspace.png` (1100 × 810), `03-empty-workspace.png` (1280 × 872), `04-increased-contrast.png` (1280 × 910).
- Source and revised implementation were opened together in the same comparison input. The concept's proportions were compared at approximately 0.861× display scale, not mistaken for a larger logical viewport. Both full windows include chrome. CSS sizing and browser checks do not apply to this SwiftUI app.
- Focused inspection at native resolution covered toolbar grouping, sidebar selection, SF Symbol badges, table columns, path wrapping, task actions and composer edges. Images were not edited to simulate interface rendering.
- [Native build, iOS shared-view typecheck and capture run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38071723190), source `e62ed0e`, macOS 26.6.2. Capture logs confirm active/key windows and Reduce Transparency off. Normal captures explicitly use regular legibility weight; the accessibility capture uses increased-contrast appearance plus bold legibility. Production inherits system preferences.

## Findings and corrections

| Prior finding | Correction | Post-fix evidence |
| --- | --- | --- |
| P1: sidebar and task panel proportions materially differed; full-height sidebar enclosed the toolbar | Native Mac `HSplitView`, inset panels, preferred 258-point sidebar and 368-point details, shared bottom baseline | Panels run from about y=62 to y=872 in `01-workspace.png`; composer ends on the same baseline |
| P1: small controls and missing Owner column changed information hierarchy | 16-point conversation/sidebar text, 14-point metadata, larger primary controls, distinct Task / Owner / Status cells | Full and narrow captures keep task ownership visible |
| P1: large black surfaces did not follow the layered slate reference | Shared blue/slate backdrop, semantic thin material panels, subtle content highlights, native Liquid Glass control surfaces | Sidebar, content, detail and toolbar remain visually continuous in the native capture |
| P2: toolbar items clustered alongside title; Pause collapsed to an icon | Native flexible toolbar spacer, explicit label style and separate SF Symbol glass controls | Search and actions occupy the trailing edge; Pause Team retains its label |
| P2: tiny badges and composer lacked the reference's visual weight | 48-point conversation badges, 62-point detail badge, rounded text field and 118 × 50 Send surface | SF Symbols and input controls are legible at reference scale |
| P2: long handoff text pushed verification below the reference's hierarchy | Brief visible route with full context in a native disclosure | Verification and task actions remain visible; instructions are not discarded |

## Required fidelity surfaces

- **Typography:** native system fonts with explicit sizes and weights; regular and bold-legibility states captured separately. Native 1× text rasterization remains visually different from the generated reference. No custom font approximations were installed.
- **Spacing/layout:** three resizable panes, inset sidebar/detail, floating toolbar groups, rounded segment control and persistent composer restored. At 1100 pixels task titles wrap into two lines; all owners and statuses remain visible, and the conversation scrolls above the composer.
- **Colors/materials:** blue selection/Send and amber pause intent; standard materials beneath real `glassEffect` surfaces. The native rendering is flatter and less luminous than the illustration. Exact reflective appearance still needs comparison on the target Mac; this is not declared a pixel-identical glass reproduction.
- **Icons/assets:** all workspace icons use SF Symbols through `Image(systemName:)` or `Label(systemImage:)`. The concept's GitHub logo and fictitious face are intentionally replaced with task/person symbols. No raster UI or handwritten imitation of those symbols is used.
- **Copy/state:** the fixture uses equivalent outcome/task names but truthful planned/offline states. Proposed handoff context is structured plan content, not a fabricated developer response. Test success, accepted handoffs, running bots and real PRs from the concept are not copied. Production starts empty.

## Comparison history

1. User rejected the prior `77aa1d0` capture. Recorded the proportions, table, typography, controls and material treatment as substantive fidelity failures.
2. `a820bc0` native capture restored structure and larger symbols but revealed over-wide side panes and toolbar clustering. Corrected both; this was a visual-QA iteration, not just compile troubleshooting.
3. `e89aed7` capture corrected pane widths, panel baseline and material hierarchy. Further refined accent hue, exact glass control shapes, title alignment and handoff density.
4. `e62ed0e` recapture checked the source and implementation together, plus narrow, empty and increased-contrast states. Remaining material/runtime acceptance limits are explicit below.

## Remaining blockers and validation

- Full Swift 6.4 / iOS 27 / macOS 27 build remains blocked because the current runner lacks the required Xcode toolchain. The isolated SDK 26 preview compiles the real views/store with a disabled model service.
- Native keyboard focus, sheets, live divider dragging, VoiceOver and compact iPhone interactions were not executed by this capture harness. Screenshots do not prove those behaviors.
- Final reflective-material fidelity requires target-device comparison; the source illustration and this CI desktop do not have identical rendering/background conditions.
- Twelve Swift 6.4 core tests passed in [validation run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38071723160). Mac view compilation and shared iOS view typechecking passed. Capture logs reported no compiler diagnostics for the final preview build; no claim of exhaustive runtime-error coverage is made.
- Test execution, PR navigation, attachments and team pause remain unavailable until their backing features exist. Disabled actions are not represented as functional.

## Checklist

- [x] Research Apple materials, glass, split containers and SF Symbols documentation.
- [x] Correct reference-scale composition and capture the actual native views.
- [x] Inspect populated, narrow, empty and accessibility appearances.
- [x] Preserve honest data and disabled service states.
- [ ] Build complete targets with the required SDK 27 toolchain.
- [ ] Verify native interactions and material appearance on target devices.

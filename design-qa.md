# Native workspace design QA — 2026-10-10

**Final result: blocked**

The selected direction is implemented in SwiftUI and captured in a real foreground Mac window. Full product acceptance remains blocked by the unavailable Swift 6.4 / iOS 27 / macOS 27 Xcode toolchain and unverified native interaction/accessibility behavior. This report does not certify a deployable app or pixel-identical rendering of the concept.

## Comparison evidence

- Source visual truth: `Documentation/Design/approved-workspace-concept.png`, 1487 × 1058 pixels, generated concept supplied as the approved direction.
- Implementation: `Documentation/Previews/01-workspace.png`, 1440 × 1012 pixels, including native window chrome; requested content frame 1440 × 960 points, captured at 1×.
- Source and implementation were opened together in the same comparison input, then inspected with the narrower and empty native captures. Both are dark, three-column windows with the same selected task. The source is about 3% wider; no claims of exact pixel matching are made. CSS viewport and browser density do not apply to this SwiftUI application.
- Focused inspection used the original full-resolution images to check the toolbar, selected task, detail text wrapping and composer. No image editing or generated replacement pixels were used for the native captures.
- Runtime: macOS 26.6.2, foreground/key window, Reduce Transparency off. `04-increased-contrast.png` explicitly uses `accessibilityHighContrastDarkAqua`; this is appearance evidence, not a full accessibility test.
- [Capture run](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38060655235), source commit `77aa1d0`.

The reference depicts active developers, passed tests and a PR. The implementation depicts an undispatched plan with disconnected services. Those intentional state differences prevent meaningful visual comparisons of running/completed colors or enabled execution actions.

## Findings and required validation

- **P1 — Production toolchain unavailable.** The required native build cannot run on the current runner. Install/select Xcode with Swift 6.4 and both SDK 27 platforms, then build the actual application targets including FoundationPlanner. The isolated preview and shared-view typecheck do not replace this check.
- **P2 — Native interactions remain unverified.** Screenshots confirm layout, not keyboard navigation, VoiceOver reading order, sheet focus restoration, live column resizing or iPhone navigation collapse. Exercise those behaviors on the production app before accepting the design as finished. The capture harness does not claim to have clicked Send, changed tabs, opened sheets or run a task.
- **Material fidelity remains provisional.** The real standard materials and glass controls are darker and less luminous than the concept. A CI desktop's background and system settings affect this appearance. Keep semantic materials; compare on the target Mac with real wallpaper, active/inactive windows, Reduce Transparency and Increase Contrast before tuning. Do not reproduce the illustration's glow using painted glass textures.

## Required fidelity surfaces

- **Typography:** native system fonts and SF Symbols replace the concept's generated approximations. Native text is smaller and denser; task titles, owners and status remain distinct. File paths wrap at the narrow detail width. Native toolbar title sizing is retained. Larger text and VoiceOver need device validation.
- **Spacing/layout:** the three-column structure, persistent composer and full-height task detail follow the source. The native sidebar is narrower and task ownership appears beneath each title rather than in a fixed table column, accommodating compact widths. At 1080 pixels the conversation scrolls and the composer remains visible; no persistent action is clipped. No separate toolbar slab or task-detail modal was introduced.
- **Colors/tokens:** dark semantic backgrounds with subtle blue ambient color; standard material for the detail surface, glass for the composer/actions. Blue Send is visible in the foreground capture. Green Run and amber Pause are intentionally unavailable until execution exists. Color is accompanied by symbols and text. System sidebar selection depends on focus and is not forced to remain bright blue when focus moves to the composer.
- **Assets:** SF Symbols are native vector icons. The unavailable GitHub task/PR integration is represented by a specialty symbol, avoiding a misleading connected-service badge. A generic person symbol replaces the concept's fictitious user portrait. No web screenshot is embedded in the app.
- **Copy/content:** outcome conversations are scoped and persisted. The app says Planned, 0 connected and Tests have not run. Preview-only data is explicitly marked. The production app starts empty. False completed/running/test/PR evidence from the illustration was not copied.

## Comparison history

1. Early captures showed opaque surfaces and inactive controls. Diagnosis found the CI runner's Reduce Transparency setting and nonforeground launch state. Those captures were not accepted as standard glass evidence.
2. Capture preferences were corrected and the preview was launched through Launch Services. macOS then required the CI shell, which already had recording access, to perform the screenshot. These were capture-environment fixes, not visual design acceptance passes.
3. Run `38060655235` produced four foreground captures. Comparison now verifies three columns, native floating toolbar groups, persistent composer, truthful task detail, empty state and narrower window composition. Full production interaction and target-SDK acceptance remain blocked as above.

## Verification

- Twelve EngineeringCore tests passed with Swift 6.4, including outcome-thread isolation and legacy-message decoding.
- Actual SwiftUI views and store compiled and ran in the Mac preview host.
- Shared views and the app entry point passed installed-iOS-simulator-SDK typechecking with the disabled preview model service.
- The production SDK 27 job failed explicitly because its required toolchain was absent.
- No browser was used: this is a native SwiftUI app, not a web prototype. Browser console checks are inapplicable. Native capture logs show foreground/key windows and four successful captures; they do not establish absence of all application runtime errors.

## Implementation checklist

- [x] Save the approved direction and design rules.
- [x] Implement native three-column navigation, selected task detail and floating composer.
- [x] Scope follow-up messages to their outcome and preserve legacy history.
- [x] Capture actual populated, narrow, empty and increased-contrast views.
- [x] Run core tests and shared-view typechecking.
- [ ] Build both complete SDK 27 app targets.
- [ ] Validate native interactions, sheets, accessibility and compact-device navigation.
- [ ] Compare material appearance on the target Mac before final visual acceptance.

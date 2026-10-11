# SwiftUI and product review — 2026-10-11

Status: UI/state improvements and full SDK 27 builds are complete. Connected-service and end-to-end product acceptance remain outstanding. See [toolchain evidence](../Engineering/Toolchain.md).

## Product and information architecture

Engineering Studio is a personal engineering workspace for one person directing eight specialists. The primary action is sending an outcome or follow-up to the coordinator. The information hierarchy is outcomes → conversation and assignments → selected task evidence. Connection state must remain visible and truthful. Planned work is never represented as running work.

The accepted three-pane composition remains the foundation. On Mac, an inset `HSplitView` preserves the reference's continuous window and independently resizable content panes. This is a deliberate layout choice, with a cost: it does not supply the standard sidebar navigation, collapse or keyboard behavior of `NavigationSplitView`. Those behaviors need native interaction validation before release. On iOS, `NavigationSplitView` provides selection-driven compact navigation and restores the three columns when space permits.

`sidebarAdaptable` was evaluated. This product currently has one primary workspace, not several peer top-level destinations; adding a TabView would duplicate navigation. Use it if future product structure introduces true peer destinations. Settings and new-outcome creation are bounded flows, not permanent tabs. Mac preferences now use the standard `Settings` scene; iOS retains a settings sheet.

## Visual system

The reference establishes composition and hierarchy. The current refinement applies the requested neutral-first design principles instead of hard-coding an illustrated blue lighting treatment.

- **Layout:** unified window toolbar; outcome sidebar; conversation/tasks and persistent composer; contextual task details. Content and toolbar share a background. Sections align to a common inset rather than adding dashboard widgets.
- **Typography:** native system fonts. Title uses title2 semibold, section headings headline, labels subheadline semibold, supporting copy callout and caption. Conversation body is 15 points on Mac and semantic body on iOS. No decorative typefaces or all-caps navigation.
- **Color:** system foreground/background and semantic materials, an accent for selection and Send, green for prepare/run intent, amber for cancel/pause intent. Labels and symbols carry the same information independently of color. Production follows the system appearance.
- **Components:** native segmented picker, native glass buttons, SF Symbols, standard multiline input, plain content rows, disclosure groups for supporting context. Task/owner/status uses columns when space permits and stacked rows at narrower or accessibility sizes. Paths remain complete and selectable.
- **Materials:** thin standard material separates content panes; regular standard material supports the composer. Interactive controls use Liquid Glass. The composer no longer nests glass inside a glass container. No custom glow, simulated reflections or decorative gradients.
- **Interaction:** use native control hover, focus, press and system presentation behavior. Cmd-N creates an outcome, Cmd-Return sends, and the standard Mac Settings command uses Cmd-comma. The composer retains focus after a successful send. No new decorative animation, looping animation or forced transition is introduced.
- **Spacing:** shared 8, 12, 16, 24 and 32 point roles; 12 point controls and 20 point containers. Primary content targets use at least 44 points; native toolbar controls retain their platform sizing. System SF Symbol badges scale with text metrics.

## SwiftUI review coverage

| Area | Finding and disposition |
| --- | --- |
| Invalidation and Observation | Composer text formerly lived on the entire conversation view. Each outcome now owns an independently observed `OutcomeDraft`; typing no longer reads or writes the workspace history. The composer is a separate view. Filtering the growing workspace still needs Instruments measurement with realistic history before further caching/pagination work. |
| State ownership | Store owns workspace and per-outcome session drafts; views own ephemeral selection, disclosures and presentation. Drafts survive switching outcomes. Sending clears only a successfully accepted draft. Failed load can retry. Current-revision save conflicts now surface rather than silently disappearing. |
| Modern APIs | `@Observable`, `@Bindable` at the editable leaf, `.task`, two-value `onChange`, `NavigationStack`, `NavigationSplitView`, Settings, native glass button styles, SF Symbols and selectable text. Both production targets now compile with Xcode 27 and Swift 6.4, including the current state initializers. |
| Composition | Removed unused duplicate work-list and plan-detail screens. Extracted `OutcomeComposer` and `TaskSummaryView`; stable task IDs drive rows. View helpers remain for small repeated sections rather than extracting every modifier. |
| Layout and large screens | Three pane widths are bounded to a usable Mac minimum. A smaller Mac conversation falls back to stacked task metadata. Accessibility text sizes force stacked rows and composer controls. iOS uses the native compact-column navigation path. Device/foldable behavior is not established by Mac screenshots. |
| Sheets and navigation | Identifiable sheet state prevents competing presentation flags. Mac Settings is a scene. New Outcome owns unsaved form text and dismisses only after successful submission. Task inspection remains inline. |
| Toolbar and window | Unified native Mac toolbar with flexible trailing action grouping; content minimum size protects the pane layout. Native controls provide system behavior. The preview host separately typechecks the production Mac scene with the installed SDK. |
| Basic, transition and advanced animation | No custom animation is necessary for the current primary workflow. No broad implicit animation is attached to workspace mutations. Native navigation and control effects remain. Reduced Motion and live keyboard/focus behavior still need interaction testing. No phase/keyframe/geometry animation was added solely to exercise an API. |
| Text and styled editing | Conversation and code-path text is selectable; messages are plain text. A rich-text editor/AttributedString document model would add unsupported product semantics and is not introduced. Long scope paths are no longer shortened to a misleading suffix. |
| Deprecated APIs | No new NavigationView, legacy one-parameter onChange or custom raster icons. No speculative SDK 27 replacements are applied without a working target compiler. Soft-deprecation guidance is a review input, not permission to break the available compiler. |
| Liquid Glass | Standard material for structural content; native glass for actions. Removed nested glass and decorative background lighting. System contrast and appearance drive foregrounds/borders. Native rendering must still be verified with Reduce Transparency and target-device conditions. |

## Validation and release blockers

`Tools/SwiftUIPreview` compiles real feature/store code with a disabled model-service replacement. Its updated pipeline requires Xcode 27 / Swift 6.4 and typechecks shared iOS views and both production scene branches with SDK 27. It is not the production target or live agent runtime; earlier captures retain their SDK 26 provenance. State regression checks cover draft identity, isolation, preservation, send ownership, save completion and retry after corrupt-load repair. Existing EngineeringCore tests remain authoritative for domain validation and persistence rules.

## Follow-up interaction review

The independent source review found concrete behavior gaps rather than a reason to redesign the accepted composition:

- Task activation now explicitly requests the compact detail column on every tap. Returning to the conversation and selecting the same task no longer depends on a changed selection ID.
- The empty outcome overlay now accounts for visible legacy messages, so migrated conversation remains readable when no outcome exists.
- Question options expose the selected accessibility trait and hide decorative radio symbols from VoiceOver.
- A new-outcome sheet with nonempty input prevents accidental interactive dismissal. Explicit Cancel remains available without another confirmation step.
- With on-device planning enabled, follow-ups automatically queue a new plan. A serial worker coalesces context, rejects stale results, respects unanswered questions and cancels queued work. Deterministic store checks cover those transitions independently of rendering; planned results still must not imply dispatch or connected developers.

The original review's decisions on semantic typography, native materials, purposeful motion, plain-text editing and the absence of peer top-level tabs remain applicable. Source corrections require native interaction verification; successful compilation alone does not prove VoiceOver announcements or compact navigation behavior.

Additional Apple references: [interactive dismissal](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)) and [selected accessibility trait](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected).

Before a production claim:

1. Complete signing/distribution and native interaction coverage. Both full SDK 27 targets, including the actual model service and utilities package, now build.
2. Complete a documented, supported personal ChatGPT subscription transport; GitHub/Linear authentication and scope enforcement; connected Swift developer execution and heartbeats; verified handoffs, tests and pull requests. These are unfinished product integrations, not UI polish.
3. Validate VoiceOver, keyboard traversal, sheets, live divider resizing, compact iPhone navigation and accessibility text sizes on native targets. Static screenshots cannot prove these behaviors.
4. Exercise lifecycle behavior on devices. Draft relaunch persistence, ordered writes, atomic send/clear and failed-save retry are implemented and regression-tested. Normal Mac quit waits for flush; force termination before a debounced write can still lose the most recent keystrokes.
5. Measure large histories with Instruments, establish UI integration coverage and verify release signing/distribution. No runtime performance improvement is quantified without profiling.

## Sources and skills

Applied SwiftUI Expert review guidance for Observation, view structure, performance, layout, navigation, text, macOS windows/scenes/toolbars, animations, accessibility, Liquid Glass and API migration. The earlier native-design work also applied the SwiftUI Liquid Glass and UI Patterns skills.

Apple documentation was consulted through Firecrawl; source pages are authoritative over inferred appearance from the concept:

- [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [HSplitView](https://developer.apple.com/documentation/swiftui/hsplitview)
- [sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable)
- [Settings scene](https://developer.apple.com/documentation/swiftui/settings)
- [ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric)
- [System SF Symbol images](https://developer.apple.com/documentation/swiftui/image/init(systemname:))

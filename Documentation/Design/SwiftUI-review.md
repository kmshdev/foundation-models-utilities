# SwiftUI and product review — 2026-10-12

This review covers app source and current native screenshots. It preserves the approved three-pane design and records concrete UX corrections. The corrections are integrated at `e64b613`; native regressions and seven captures passed. Source changes, builds, rendered captures, assistive-technology interaction and live account behavior are separate evidence.

## Product and layout

Engineering Studio gives one person an outcome-based conversation with a coordinator and eight focused specialists. Sending an outcome/follow-up is the primary action. Availability, independent scope, handoffs and evidence belong beside the conversation.

Mac uses a continuous window, unified toolbar and three inset `HSplitView` panes. iPhone/iPad use `NavigationSplitView` with sidebar/content/detail selections and an explicit preferred compact column. Selecting the same task after returning must reopen details. Detail identity must include outcome and task so unrelated tasks with the same ID cannot share action/disclosure state.

The Mac container preserves the accepted rounded composition. A native selectable List supplies sidebar selection; a toolbar button and Cmd-Control-S toggle its visibility. Divider resizing and keyboard traversal still require interaction evidence. Narrow conversations stack assignment metadata; wide windows constrain the conversation and composer to 760 points. No genuine peer navigation hierarchy currently justifies a tab bar or `.sidebarAdaptable`.

## Design system

The [design system](README.md) defines native typography, neutral surfaces, functional color, SF Symbols and 8/12/16/24/32-point spacing. Title2, headline, subheadline, callout and caption provide hierarchy. Mac conversation body is 15 points; iOS body is semantic. Metadata stays secondary without hiding blockers/errors.

Structural content uses standard materials; actions use Liquid Glass. Thin panels and a regular-material composer express hierarchy; glass toolbar groups/buttons express interaction. Appearance and contrast remain system-driven. Message metadata and team status now reflow at accessibility sizes; task rows and composer already have adaptive variants. Labels/symbols supplement functional color; decorative images are hidden from accessibility.

## Review and corrections

| Area | Source finding and disposition |
| --- | --- |
| Observation/invalidation | Stores, account connections and runtime use `@Observable`. `OutcomeComposer` uses an editable `@Bindable` draft leaf; typing is isolated from conversation filtering. Runtime is a compound snapshot, so changed receipts can invalidate readers of that property. No Instruments evidence establishes a performance improvement or need for additional caches. |
| State flow | Workspace, questions, plans and drafts belong to the store; per-window selection, sheets and disclosures belong to views. Ordered persistence, stale-plan rejection and cancellation are implemented. New-outcome drafts use stable owned state and backward-compatible durable workspace storage; creation and draft clearing share one snapshot. |
| Execution history | `ExecutionResultsView` requires exact task equality for current progress. Unmatched receipts remain in Previous executions with an explanation. `ExecutionResultRow` shows observed status, specialty, actual local commit, summary and blocker without invented tests/PRs. Runtime reads stay in assignment, result, control and inspector leaf views. |
| Team presence | `TeamMemberRow` wraps text and distinguishes disconnected, available, working and stale presence. Stale active-task observations no longer claim current work. Configured specialties and actual availability remain separate. |
| Runtime controls | Team pause is independent of planning cancellation, with Restart/Connect exposed when appropriate. Single-flight controls reject conflicting actions and fence stale snapshot/delivery replies. Native checks cover repeated Pause, conflicting Restart, delayed snapshots, failed reads and local shutdown. Catalog replacement also awaits the account/model shutdown hook before publishing another selected model. |
| Setup discoverability | Explicit first-launch New outcome and contextual planning-model/runtime actions lead to existing native forms. The Mac toolbar retains the team control's visible intent label. |
| Conversation scroll | A Bool geometry threshold and user scroll phase preserve reading position. Incoming messages follow while the user is near the bottom; otherwise a new-message action offers an explicit return. Sending reveals the latest content. Keyboard and repeated-update behavior need interaction checks. |
| Navigation/sheets | Identifiable routes prevent competing sheets. Mac Settings is a scene; bounded creation/iOS settings use native presentation. Flows own dismissal. Durable new-outcome drafts protect text without adding routine confirmation gates. Task inspection stays in the hierarchy. |
| Toolbar/window | Unified native toolbar, flexible action grouping and platform controls preserve the continuous container. The fixed 116-point title offset is removed. Shortcuts are Cmd-N, Cmd-Return, Cmd-Control-S and Cmd-comma. Divider resizing, overflow, focus and multi-window behavior require interaction evidence. |
| Basic/transition/advanced animation | Native controls/navigation supply purposeful feedback. There is no broad implicit animation on workspace mutations or decorative phase/keyframe animation. Explicit scroll animation must be scoped and disabled for Reduce Motion. System effects alone do not establish a complete motion audit. |
| Styled text/editing | Instructions are plain multiline text. Conversation, paths and command output are selectable. A rich-text `AttributedString` document model would add unrequested semantics; API availability is not a reason to replace the input. |
| Modern SDK APIs | Observation, `.task`, two-value `onChange`, `NavigationStack`, `NavigationSplitView`, Settings, `ToolbarSpacer`, shared toolbar background visibility, native glass styles, `GlassEffectContainer` and `ViewThatFits` are used. SDK 27 builds validate availability. New APIs should serve an actual behavior. |
| Deprecated/soft-deprecated APIs | No hard-deprecated SwiftUI API was found in the reviewed features. No legacy NavigationView, one-argument onChange, blanket animation or raster workspace icon is introduced. SDK 27 item-driven alerts could simplify the failure binding; this is scoped maintenance, not a functional blocker. Soft-deprecations remain informational and require behavior/availability checks before migration. |
| Accessibility | Selected task/answer traits, descriptive control labels, decorative-image hiding, semantic status and wrapping layouts are implemented. Captures show rendered layout, not VoiceOver order/announcements, Full Keyboard Access, Reduce Transparency or real device keyboard behavior. |

## Model and integration facts

Direct Swift ChatGPT OAuth/PKCE, protected Keychain profiles, rotating refresh, the actual account model catalog and Responses streaming are implemented. The `LanguageModel` adapter uses the real Foundation Models framework and guided planning profile. Authentication is not a Mac/Node service; an API key is not substituted for a subscription.

The Swift coordinator, eight observed developer threads, isolated scoped worktrees, durable handoffs, interrupted-delivery recovery, immutable draft PR publication and phone bridge are implemented. Native GitHub/Linear settings use device Keychain; public GitHub reads do not require a token. The remote host owns execution/model credentials. Live browser consent, account entitlement/inference, complete developer turns and an active Cloudflare route remain operational validation, not missing implementation disguised as design placeholders.

## Evidence and remaining checks

At final application source `e64b613`, [both full native builds and 119 portable tests passed](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38193065476); [both scene branches, native regressions and seven captures also passed](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38192295529). Production Mac startup passed separately. The current iPhone startup diagnostic timed out installing into an unresponsive hosted simulator before the app launched; earlier phone evidence remains tied to its original commit. See [NativeBuild](../NativeBuild/README.md).

The preview pipeline compiles real utilities, adapter, features, state and service/runtime code. Native checks exercise deterministic transports, framework planning, cryptography, isolated Keychain records, loopback framing and runtime lifecycle. There is no disabled planner replacement standing in for model integration. Screenshot fixtures do not authenticate or dispatch developers.

Two additional capture cases are configured:

- `06-wide-workspace.png`: 1600 × 950 points, dark appearance.
- `07-accessibility-workspace.png`: 1280 × 950 points, dark appearance, `DynamicTypeSize.accessibility2`.

Both cases were generated successfully. Inspection confirmed bounded conversation/composer width and stacked task/message metadata without sidebar or inspector overflow. Other previews cover normal dark, narrower Mac, empty workspace, increased contrast and light appearance. Mac accessibility-size capture does not establish iPhone Dynamic Type or compact keyboard behavior. The final captures also confirm the team action retains its visible label at both normal and narrower widths.

Remaining interaction evidence covers first outcome creation, draft dismissal/relaunch, contextual setup, task selection/reselection, pause/restart, reading-position preservation, dividers, native keyboard traversal, VoiceOver, Reduce Motion/Transparency and compact-device behavior. Signed distribution, sandboxed host tools and account consent have operational requirements. No runtime performance result is quantified without profiling.

## Sources and skills

Applied SwiftUI Expert guidance for Observation/invalidation, composition, resizable layout, navigation/sheets, macOS scenes/views/window/toolbars, editing, accessibility, Liquid Glass, animation and API migration. Apple HIG/API pages were read through Firecrawl; primary documentation governs behavior rather than the apparent color of the concept.

- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [HSplitView](https://developer.apple.com/documentation/swiftui/hsplitview)
- [Settings](https://developer.apple.com/documentation/swiftui/settings)
- [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [TextEditor](https://developer.apple.com/documentation/swiftui/texteditor)

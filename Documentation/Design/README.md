# Engineering Studio product design

Engineering Studio is a native iPhone, iPad and Mac engineering workspace for one person directing eight development specialists. Its primary action is to send a shared outcome or follow-up to the coordinator. The workspace connects that conversation to scoped assignments, availability, handoffs, blockers, commands and pull requests.

The implementation uses Swift 6.4 and SwiftUI with the iOS 27 and macOS 27 SDKs. Production starts with an empty local workspace. Missing connections must never become simulated activity.

## Layout and hierarchy

The accepted composition is outcomes → conversation and assignments → selected task evidence. The [approved image](approved-workspace-concept.png) defines composition; its people, successful tests and PR are example data.

- **Mac:** three independently resizable panes in an inset `HSplitView`, beneath a unified window toolbar. A native selectable sidebar supports keyboard selection and a toolbar toggle. Content continues through the window. Rounded structural panels separate sidebar and details without a second contrasting header. Preferences use the native `Settings` scene.
- **iPhone and iPad:** `NavigationSplitView` expresses the same selection hierarchy. Compact layouts navigate between columns; wider proposals can display them together. Task inspection belongs to this hierarchy rather than a modal conversation overlay.
- **Conversation:** a native segmented control switches conversation/tasks. Assignment rows show separate task, owner and status columns when space permits, with stacked compact/accessibility metadata. A persistent composer belongs to the selected outcome.
- **Task evidence:** scope, handoff, developer result, commands, changes and PR receipt. Disclosure groups preserve supporting context without making every detail compete for attention.

There is one primary workspace, so a `TabView` with `.sidebarAdaptable` would duplicate navigation. Adopt that style only if the product gains genuine peer destinations.

## Typography, spacing and color

Use the native system font and a small hierarchy: title2 semibold for titles, headline for sections/tasks, subheadline semibold for author/action labels, callout for supporting content and caption for timestamps/evidence. Conversation body uses 15 points on Mac and semantic body on iOS. Paths and command output can use monospaced text; ordinary status prose does not.

Shared spacing roles are 8, 12, 16, 24 and 32 points. Controls use a 12-point corner role; structural containers use 20 points. Align related text to a common leading edge, let rows grow for wrapping text, and use whitespace/separators rather than adding dashboard cards. Primary content interactions generally provide 44-point targets; native toolbar controls follow platform sizing.

Follow system appearance and contrast. The accent identifies selection and Send; green indicates run/resume intent and completed status; amber indicates pause/cancel intent or attention; red identifies errors. Color supplements labels and SF Symbols. Avoid a decorative blue backdrop, fixed glass colors, gradients and custom glow.

## Components and materials

Workspace icons use `Image(systemName:)` and `Label(systemImage:)`. Decorative badges are hidden from accessibility. Do not copy the concept's third-party logo or portrait into a system icon.

Use native buttons, secure fields, multiline input, segmented pickers, forms, links and disclosure groups. Reuse the observed status component in task rows and details. Separate leaf views isolate composer text, message metadata, developer presence and execution receipts.

Standard materials provide content structure: thin material for panels/assignment containers, regular material for the composer. Liquid Glass belongs to interactive controls and toolbar groups. Use native `.glass` and `.glassProminent` styles and `GlassEffectContainer` when nearby custom glass controls share a sampling region. Apply glass after layout and interactive glass only to interactive content. The composer is a standard-material surface containing a glass Send button, rather than nested glass layers.

Choose material by semantic role, not apparent screenshot color. Let the system respond to appearance, window activity, Increase Contrast and Reduce Transparency. Default sheets retain native material behavior.

## Interaction and truthful feedback

Use native press, hover, focus, disclosure and presentation behavior. Cmd-N starts an outcome, Cmd-Return sends, Cmd-Control-S toggles the Mac sidebar and Cmd-comma opens Mac settings. Instructions remain plain multiline text; rich-text formatting has no established product role. Sent content remains selectable.

Bounded flows use identifiable sheet routes and own dismissal. Local selection/disclosure state remains separate from persistent outcomes. Conversation and new-outcome drafts persist. Closing the creation sheet retains its draft; creating an outcome saves the accepted text and clears its draft in one ordered snapshot.

Workspace controls separate Pause, Restart and Connect from planning cancellation, offer contextual setup actions, preserve reading position and separate current execution results from previous assignments. The conversation and composer stop growing at a readable width on larger windows. See the [SwiftUI review](SwiftUI-review.md) for implementation/validation status.

A configured specialty is not availability; a saved plan is not dispatch; a command exit is not an inferred test count; and a PR link needs a verified receipt. Historical results remain historical. Swift ChatGPT sign-in and the Foundation Models adapter are implemented on both platforms. The separate host executes developer work and exposes the Swift phone bridge. Native settings/Keychain own credentials, not repository secrets.

## Evidence and references

[Production launch evidence](../NativeBuild/README.md) and [fixture previews](../Previews/README.md) are distinct. The preview host compiles real Foundation Models utilities, adapter, features and state, and runs deterministic native checks. Fixtures do not sign in or dispatch developers. Wide/accessibility cases are configured in `Apps/EngineeringStudio/Tests/NativePreviewHost/PreviewHost.swift`; outputs become evidence only after a successful capture.

Apple sources: [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview), [HSplitView](https://developer.apple.com/documentation/swiftui/hsplitview), and [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

# Codex plugin

`interfaces@interfaces` is installed and enabled through the Codex plugin manager, version **1.10.3**. Source: [jakubkrehel/skills](https://github.com/jakubkrehel/skills), pinned commit `c0588bb6d654eb725046f0bf9deec338c34891ab`.

The upstream Claude-compatible marketplace and plugin manifests are accepted directly by Codex CLI `0.159.0-alpha.3`; no application runtime or second agent client was installed. Installation was verified with `codex plugin list --marketplace interfaces --json` (`installed: true`, `enabled: true`). The managed plugin cache is outside this Swift app repository. New Codex sessions discover the plugin; this hosted chat's preloaded tool/skill catalog is not rewritten by a local CLI install.

## Skills included

better-interface, better-ui, better-typography, better-colors, better-accessibility, better-layout, better-writing, interface-review, explain-interface, break, build-design, state-machine, variant.

## App-specific use

Use interface-review for changed SwiftUI surfaces; use individual better-* domains for bounded reviews, build-design for the accepted native image, and variants only when the user requests alternatives. Do not run every overlapping review on every edit. Translate web examples into SwiftUI, SF Symbols, VoiceOver, keyboard focus, Dynamic Type, `accessibilityReduceMotion`, previews and native screenshots. A temporary web page or HTML artifact does not establish native UI behavior.

The repository AGENTS.md and user directions govern workflow: infer routine implementation choices, do not introduce repeated confirmation gates for token rounding or native component choice, and keep missing data/actions honest. Follow Apple HIG for native semantics. Do not copy fictitious test passes, running developers or GitHub logos from design concepts.

## Reinstall

```sh
codex plugin marketplace add jakubkrehel/skills --ref c0588bb6d654eb725046f0bf9deec338c34891ab --json
codex plugin add interfaces@interfaces --json
codex plugin list --marketplace interfaces --json
```

# Codex skill catalog

Installed on 2026-10-11 for Codex using **skills CLI 1.7.2**. All 21 requested skills are enabled and individually discovered by the current Codex CLI app-server `skills/list` with `forceReload: true`; zero duplicate requested names and zero parse errors. The current chat’s advertised tool/skill catalog is not automatically refreshed by this disk installation. New or refreshed local Codex sessions can discover these files.

## Installation scope

- Canonical user path: `/home/agent/.agents/skills/<name>/SKILL.md`. This is the skills CLI’s global location for Codex; the actual Codex home is `/run/codex-environment/codex-home`, and its app-server confirmed this canonical path is discoverable.

- Every install selected only `--agent codex --global --copy`; no other agent was selected or configured. The common `.agents` directory is not an access-control boundary: another tool deliberately scanning it could read it. No other-agent folders, global agent instructions, lifecycle hooks or MCP configurations were installed.

- Source checkouts and installation helper scripts live under `/workspace/agent-tooling-sources/skills`, outside the Swift app repository. Existing skills were preserved. Nested duplicate skills and alternative-agent/plugin packaging from `swiftui-pro` and `ios-agent-skill` were excluded from their skill copies. The separately requested interfaces plugin is tracked independently.

- Exact upstream commits, source paths, installed hashes, local adaptations and discovery results are in [skills-provenance.json](skills-provenance.json). Source licenses are retained under [licenses/skills](licenses/skills). Craft has no root license file in the pinned source; it remains a local user-requested installation, with source attribution, not a vendored app dependency.

## Routing

Load the smallest relevant skill. A roster of installed skills is not an instruction to load every skill or execute its workflow. Prefer `swiftui-pro`, the provided SwiftUI Expert plugin and Apple documentation for UI work; `sota-swift`/`write-swift` for Swift correctness; and bounded task-specific skills for testing, documents, planning or motion.

| Installed name | Role | Source |
|---|---|---|
| `craft-design-engineering` | Purposeful component details; web recipes translated to native semantics. | [Pinned source](https://github.com/gustavo-fior/craft/blob/e0d176e163fb2236b3de9415aaf73ea3aab09d1c/skills/craft-design-engineering/SKILL.md) |
| `swiftui-pro` | Primary SwiftUI review; verify SDK declarations rather than treating version claims as evidence. | [Pinned source](https://github.com/twostraws/SwiftUI-Agent-Skill/blob/f9800713b24580bc444931949aad4519128605e8/swiftui-pro/SKILL.md) |
| `sota-mobile` | Native platform lifecycle, offline behavior, release and security checks. | [Pinned source](https://github.com/martinholovsky/SOTA-skills/blob/6e96ea8af1a3f8bb4d2cc5fc8869672c943ab4cb/skills/sota-mobile/SKILL.md) |
| `sota-swift` | Swift language, concurrency, memory and package correctness. | [Pinned source](https://github.com/martinholovsky/SOTA-skills/blob/6e96ea8af1a3f8bb4d2cc5fc8869672c943ab4cb/skills/sota-swift/SKILL.md) |
| `orchestrate-batch-refactor` | Bounded independent work packets and ownership during broad refactors. | [Pinned source](https://github.com/Dimillian/Skills/blob/05ba982bfeb0d77d3c97d4542b0ee15034d05f84/orchestrate-batch-refactor/SKILL.md) |
| `agent-memory-repo` | Explicitly invoked local memory, separate from the app repository. | [Pinned source](https://github.com/AgentMemoryRepo/agentmemoryrepo/blob/8798cb26c817d451a5ed6cba0ad8d9eca8d5ec3e/skills/agent-memory-repo/SKILL.md) |
| `ios-agent-skill` | Apple framework research and implementation guidance; optional MCP tools are not installed. | [Pinned source](https://github.com/Nagarjuna2997/ios-agent-skill/blob/26369af889b27914d87342a1922bcac3b2921f5a/SKILL.md) |
| `harness-eval` | Deterministic harness validation first; no repeated scope questionnaire. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(development)/harness-eval/SKILL.md) |
| `not-your-babysitter` | Evidence-driven autonomous execution with concise progress updates. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(development)/not-your-babysitter/SKILL.md) |
| `gh-fix-ci` | GitHub Actions diagnosis, scoped repair and verification. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(tooling)/gh-fix-ci/SKILL.md) |
| `create-adr` | Record decisions and consequences using repository conventions. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(creation)/create-adr/SKILL.md) |
| `create-rfc` | Compare unresolved architecture alternatives without inventing acceptance. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(creation)/create-rfc/SKILL.md) |
| `technical-design-doc-creator` | Describe system boundaries, contracts, risks and implementation sequencing. | [Pinned source](https://github.com/tech-leads-club/agent-skills/blob/6df68d52028b9261058231e0f4998048c0352f45/packages/skills-catalog/skills/(creation)/create-technical-design-doc/SKILL.md) |
| `planning-with-files` | Manual task-owned durable plans, no Claude lifecycle hooks. | [Pinned source](https://github.com/OthmanAdi/planning-with-files/blob/7056ed2f2b86a8a9e18840f625ac66a48fa07693/skills/planning-with-files/SKILL.md) |
| `component-extract` | Converted raw Markdown to a native SwiftUI component inventory skill. | [Pinned source](https://github.com/Trystan-SA/claude-design-system-prompt/blob/3c3ddb07d7aa3fef051d83608596470c95cfd8fe/codex/skills/component-extract.md) |
| `design-system-extract` | Converted raw Markdown to semantic SwiftUI token extraction. | [Pinned source](https://github.com/Trystan-SA/claude-design-system-prompt/blob/3c3ddb07d7aa3fef051d83608596470c95cfd8fe/codex/skills/design-system-extract.md) |
| `apple-design` | Fluid, accessible interaction principles; web implementation examples are reference only. | [Pinned source](https://github.com/boraoztunc/skills/blob/645553ca7622570479e330cc089c65fcf34e0ba8/apple-design/SKILL.md) |
| `write-swift` | Modern Swift implementation and review, checked against the actual toolchain. | [Pinned source](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/write-swift/SKILL.md) |
| `animation-vocabulary` | Shared motion terminology with no decorative motion mandate. | [Pinned source](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/animation-vocabulary/SKILL.md) |
| `find-animation-opportunities` | Read-only search for useful motion, rejecting unnecessary animation. | [Pinned source](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/find-animation-opportunities/SKILL.md) |
| `improve-animations` | Evidence-based motion audit; implement only within requested scope. | [Pinned source](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/improve-animations/SKILL.md) |

## Local adaptation contract

Each installed `SKILL.md` starts with an Engineering Studio adaptation that explicitly supersedes conflicting upstream workflow suggestions. The original entry point is retained as `UPSTREAM-SKILL.md` for provenance, not as a second discoverable skill.

1. The user’s current scope, system/developer instructions and repository `AGENTS.md` govern. Already-authorized reversible work proceeds without new routine approval gates; reuse recorded answers and wait for genuinely needed input. No generic skill grants external publication, secret access, destructive actions or background execution.
2. All app, coordinator, model transport and developer execution code is Swift. Native SwiftUI, SF Symbols, Apple HIG, semantic materials and verified SDK availability govern. CSS, React, Android and web examples are conceptual references only.
3. Preserve the approved three-pane structure and latest neutral, professional design principles. Color expresses actions/status. Motion must serve comprehension and respect Reduce Motion; test Dynamic Type, Increase Contrast and Reduce Transparency. Do not introduce decorative textures, gradients or web shells.
4. Codex uses available tools, not hypothetical `AskQuestion`, Claude `/commands`, hook events or optional MCP names. Missing tools are a limitation to route around, not permission to install extra services. Keep helper runtimes outside this Swift repository.
5. Evidence must distinguish a plan from dispatch, local state from connected service state, a conceptual design from a rendered app, and core/typechecking from complete native target validation.

Specific corrections: `gh-fix-ci` no longer requires a second approval to implement an authorized repair; `harness-eval` defaults to Track A and omits optional documents; `planning-with-files` removes Claude hook metadata; `ios-agent-skill` cannot automatically open public issue drafts; document skills reuse existing facts; motion skills do not stall authorized implementation behind new selection gates. Installing `agent-memory-repo` does not create or push memory.

## Reinstall and update

Resolve each `source_repository` at its recorded `source_commit`, select only its recorded `source_path`, then use:

```sh
npx --yes skills@1.7.2 add <pinned-local-skill-directory> --agent codex --global --yes --copy
```

Before reinstalling, preserve any local changes and check for name collisions. Reapply this adaptation contract; the two extraction entries additionally need valid `name`/`description` frontmatter and native SwiftUI output guidance. Remove nested duplicate/alternative plugin packaging as recorded. Validate with Codex `skills/list` and check each expected name appears once, enabled, with no parse errors. A blind `skills update` can overwrite adaptations; review changes before replacing the installed copies.

No skills in this set are missing or blocked. Installation verifies discoverability and metadata; it does not certify all upstream advice, execute the skills, connect optional services, or prove the app production-ready.

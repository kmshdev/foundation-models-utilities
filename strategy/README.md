# Engineering Studio development strategy

Deliver a native personal engineering coordinator: accept outcomes, divide them into non-overlapping work, observe real developer availability, transfer context and report verifiable results. Application implementation stays Swift 6.4 and SwiftUI for iOS/macOS 27.

This directory adapts the upstream Agency Agents strategy structure—focused playbooks, coordination contracts and scenario runbooks—to this repository. It is an operating guide for Codex development, not evidence that app integrations are connected.

## Start here

1. Read `AGENTS.md`, inspect the working tree and identify the user's current outcome and retained answers.
2. Choose a [runbook](runbooks.json) and only the necessary [roles](agent-catalog.md). Keep the eight in-app specialties unchanged. The 24 Codex profiles are a selectable development library.
3. Record task ownership and dependencies using the [coordination contract](coordination/handoff-templates.md). Start disjoint work when slots actually exist; the configured ceiling is eight, and the host's lower limit always wins.
4. Follow the [delivery playbook](playbooks/native-delivery.md). Continue within existing authorization; these documents introduce no phase approval gates.
5. Verify the result at the appropriate layer, integrate changes, and report completed behavior, evidence and remaining blockers.

## Repository boundaries

| Area | Purpose |
| --- | --- |
| `Apps/EngineeringStudio/Core` | Leaf contracts, persistence/networking primitives, native UI primitives and FoundationModelsUtilities |
| `Apps/EngineeringStudio/Services` | Domain adapters, model/authentication transports, runtime infrastructure and MCP client |
| `Apps/EngineeringStudio/Workflows` | Cross-service planning, publication, developer dispatch and lifecycle orchestration |
| `Apps/EngineeringStudio/Features` | Public feature entry points and native SwiftUI implementations |
| `Apps/EngineeringStudio/App` | Scenes, deep-links, assets and dependency composition |
| `Apps/EngineeringStudio/Tests` | Portable/MCP tests and the native regression/capture host |
| `Tools` | Swift build, launch and capture utilities |
| `.github/workflows` | Build and verification metadata |
| `.codex/agents` | Codex development profiles, loaded by compatible Codex sessions |

The repository allowlist is `kmshdev/foundation-models-utilities`; upstream Apple utilities are a research/reference source. The selected Linear project is **Engineering Workflow Automation**. Resolve actual project and issue identifiers before writes; a saved name does not establish access. Honor explicit order, urgent defects, dependency blockers, then Linear priority.

Follow the [module map](../Documentation/Engineering/Module-architecture.md): migrate Core → Services → Workflows → Features → App, and use exposed feature APIs for peer feature calls. The app package manifest enforces dependency direction.

## Tooling and persistence

- [Agent catalog and conversion](agent-catalog.md): 24 profiles, upstream converter evidence and provenance.
- [Skill catalog](skill-catalog.md): requested Codex-only installations, source pins and native adaptations.
- [Plugin catalog](plugin-catalog.md): the installed Interfaces Codex plugin and its 13 skills.
- [Current evidence and remaining work](current-state.md): separates what runs from what remains to build.

Repository profiles and strategy persist in Git. Global skills and the plugin are installed in this development environment, outside app source; a fresh machine needs reinstallation from the catalog pins. An existing hosted chat does not acquire new preloaded tool types merely because the local CLI discovers them. Use available runtime tools and provide the appropriate profile instructions when delegating.

# Native delivery playbook

These stages describe evidence and dependencies, not mandatory meetings or approval gates. Small fixes can combine stages.

## 0 — Inspect

Read the outcome, current source, working tree, retained choices and relevant existing tests. Identify what is already implemented. Use Codebase Onboarding only when unfamiliarity is a real blocker; use Research Synthesist for a bounded unanswered question with primary sources.

## 1 — Define

Translate the outcome into observable acceptance criteria and a small dependency graph. Product Manager resolves product scope; Master Plan Architect organizes substantial delivery. Preserve priority: explicit order, urgent defects, dependency blockers, Linear priority. Ask only for essential missing decisions; do not reopen settled repository, platform, specialty or model-access preferences.

## 2 — Establish contracts

Software Architect defines shared Swift boundaries. Multi-Agent Systems Architect handles runtime ownership, presence, retries and handoffs; Workflow Architect defines user-visible states. Avoid three overlapping architecture reviews for a small feature. Assign shared files to one writer before parallel implementation.

## 3 — Implement

Mobile App Builder owns native features; Backend Architect owns scoped Swift adapters; Tooling Engineer owns Swift tooling and CI. Universal Document Compiler or Knowledge Graph Engineer joins only for a real document or relationship-index requirement. Minimal Change Engineer handles bounded defects. Use the minimum agents needed and respect available slots.

Read current Apple docs and relevant SwiftUI/concurrency skills before API choices. Use SF Symbols, semantic materials, native split-view navigation, floating glass controls and content continuity consistent with the accepted design. Keep deliberate action tints, keyboard focus, VoiceOver, Dynamic Type and Reduce Motion. UI Designer owns shared appearance; UX Architect owns navigation; Storyteller and Whimsy refine communication and feedback only where useful.

## 4 — Verify

Run meaningful portable tests for coordination changes. Build both production targets with Xcode 27 / Swift 6.4. Use native previews or actual app captures for visual changes; label fixtures and compiler stubs accurately. Reality Checker compares claims to evidence independently. Tool Evaluator is for a specific tool decision, not a standing gate. Workflow Optimizer investigates measured repetition or latency.

Current CI uses the `xcode-27` image. The optional `capture_launch` diagnostic is bounded and separate from mandatory builds. An unavailable simulator should not halt unrelated app or core work. Refer to `Documentation/Engineering/Toolchain.md` for toolchain fallback and limitations.

## 5 — Integrate

Inspect the final diff for ownership conflicts, regressions, unrelated files and unsupported success claims. Git Workflow Master integrates within current authorization; Technical Writer updates behavior and setup documentation; DX Engineer checks the developer path where it changed. Do not add an approval ceremony absent from the user task. Do not infer external communication permission from an installed skill.

## 6 — Operate and learn

Report evidence and remaining blockers. Persist useful decisions in existing architecture docs or a focused ADR when a durable tradeoff warrants it. Use agent memory for stable facts with provenance, never credentials or unverifiable assertions. Keep the user's source of truth and avoid parallel stale plans. New work enters the same scoped flow rather than activating all 24 roles automatically.

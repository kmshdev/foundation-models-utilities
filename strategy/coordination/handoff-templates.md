# Assignment and handoff contract

The coordinator keeps one short ledger for the active outcome. Use the current session plan or an existing Linear issue; do not create a second permanent tracker for every small edit.

## Assignment

```text
Outcome / ticket:
User-visible acceptance criteria:
Owner / role / live session:
Owned files and symbols:
Read-only dependencies:
Depends on / next receiver:
Base commit:
Validation required:
Known constraints and retained user choices:
Status: queued | running | blocked | ready-for-review | complete
```

Availability comes from actual sessions or executor presence. A configured role is not an available bot. Give each requirement one owner. Two tasks may inspect the same file; only one may modify it at a time. Shared contracts, the Xcode project and `StudioStore` require explicit ownership transfer between agents, not another user approval. If an unexpected dependency appears, report the exact path and reassign or serialize it.

## Handoff

```text
Outcome / task:
From -> to:
Base / head commit or current diff:
Owned paths released:
Behavior and contract changes:
Acceptance criteria met / remaining:
Commands, toolchain, target and results:
Evidence paths / CI run / PR URL:
Known failures, not-run checks and assumptions:
Next action and required input:
```

The receiver checks the diff and relevant evidence before building on the result, then accepts or returns a precise defect. Retry only when a changed hypothesis justifies it; after repeated identical failure, isolate the blocker and continue independent work. Never pass credentials through a handoff.

## User update

Report the changed behavior first, followed by current progress, a concrete blocker if present, test/build evidence and real PR links if any. Planned tests are **not run**; a failure is **failed**; missing infrastructure is **blocked**. A screenshot proves only what it visibly shows. Do not turn unverified UI labels into evidence of external delivery.

For genuinely blocking missing information, use the available interactive chat question tool, group related questions, retain answers and wait before dependent work. Routine choices and previously answered questions do not need another prompt. External messages and account operations still require the authority supplied by the user's actual task; profiles cannot grant it.

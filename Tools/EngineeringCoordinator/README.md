# Engineering coordinator

A private Cloudflare Agents service for eight developer roles. The user's confirmed scope is `kmshdev/foundation-models-utilities` and the Linear **Engineering Workflow Automation** project (`c655b4e0-e003-424a-a29a-3674e9a3983b`). The user removed earlier approval checkpoints. This service does not add approval waits.

The service is a working orchestration layer. It does not pretend that a configured role is an authenticated model or a running developer. Every role starts offline. A real executor must authenticate, heartbeat, claim work, and return observed evidence.

## What it does

- Stores outcomes, structured plans, assignment state, handoffs and a bounded event history in a SQLite-backed Cloudflare Agent.
- Gives each requirement one specialist and file/directory ownership. Overlapping paths require an explicit dependency; unfinished plans cannot compete for the same paths.
- Limits active execution to three tasks. Prioritizes explicit user order, urgent defects, tasks blocking dependencies, then Linear priority.
- Uses separate owner and role-scoped runner credentials. Rejects stale ownership tokens, direct state replacement, cross-role writes and unknown routes.
- Passes versioned results to dependent specialists. The recipient must acknowledge the exact commit before it can claim dependent work.
- Requires test evidence and checks the changed-file scope and PR destination before marking a task complete. It records executor-reported evidence; it does not independently attest that an external machine actually ran a command.
- Persists a batch of questions until every answer arrives. This API state is separate from the current ChatGPT client's interactive question controls.
- Stops dispatch when paused. It preserves existing ownership until the executor is confirmed stopped, then advances the fencing token during recovery.

## Local operation

Node 22+, `npm ci`, `npm run types`, `npm test`, `npm run check`, `npm run build`, then `npm run dev`.

Create `.dev.vars` with independent randomly generated `OWNER_TOKEN` and `RUNNER_SIGNING_KEY` values of at least 32 characters. Optional `GITHUB_TOKEN` and `LINEAR_TOKEN` credentials belong in the secret store. They are not inherited from the user's connected ChatGPT apps. Never commit this file or paste its contents into chat. `wrangler types` infers secret types from `.dev.vars`.

Production deployment is configured with `workers_dev: false` and preview URLs disabled. Enable only the required authenticated route during deployment. Both the Worker and Agent enforce authorization before returning room data. There is no unauthenticated dashboard.

## API

All requests require `Authorization: Bearer …`. JSON bodies are capped at 64 KiB. Owner endpoints: `POST /v1/outcomes`, `/plans`, `/pause`, `/recover`, `/questions`, `/answers`, `/runner-token`; `GET /v1/status`, `/integrations`. Runner endpoints: `POST /v1/heartbeat`, `/claim`, `/progress`, `/complete`, `/handoffs/ack`; `GET /v1/status` returns only the runner's own assignments and incoming handoffs.

A runner token is valid for 24 hours and identifies exactly one configured specialist. `/v1/runner-token` takes `{ "botId": "architecture" }`. Keep returned tokens in the executor's secret environment. Tokens are bearer credentials; rotate the signing key to invalidate all outstanding runner tokens.

See the runtime integration tests for a complete intake → plan → claim → evidence → handoff → next-owner sequence. No task is automatically generated from free text yet: a connected planning harness must read the outcome and submit a schema-valid plan. GitHub/Linear access probes are implemented; durable publication of tickets and PRs is not yet implemented in this first slice.

## Executor contract

`runner/agent.mjs` is a transport and lifecycle adapter for a separately authenticated coding harness. Set `COORDINATOR_URL`, `RUNNER_TOKEN`, `ENGINEERING_HARNESS` (trusted executable path) and optionally `RUNNER_STATE_DIR`. The harness receives one JSON assignment on stdin, including required acceptance checks, owned paths, repository and incoming commit evidence. It must use an isolated worktree, execute the work, and write a single evidence JSON object on stdout. Send logs to a local file or stderr, with secrets redacted.

Evidence fields: `commit` (40-character SHA), `summary`, `changedFiles`, `tests` (`command`, `status`, `detail`) and optional `pr`. The adapter stops the child process group if its heartbeat fails. It retains a checkpoint on a crash or failed task and refuses to silently start again until that task is reconciled. It does not implement an OS sandbox; deploy it only in a suitably isolated executor. Repository scripts cannot be trusted merely because the model selected them.

## Model access and remaining activation work

Use the official personal/self-hosted Sign in with ChatGPT integration, with one renewable-session owner. The Mac example in the DevKit is not a platform requirement. Keep ongoing inference and credential refresh separate from Apple build workers. The official self-hosted flow is documented at https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms . A custom hosted callback is not interchangeable with the OSS loopback flow. Exact Cloudflare inference-host eligibility still requires validation.

The current code deliberately does not embed unverified OAuth shortcuts or the noncommercial DevKit code. It also does not reuse the assistant session's credentials. To activate developer execution, connect a correctly authenticated model/coding harness, isolated execution environment, and scoped GitHub/Linear runtime credentials. Xcode/Swift 6.4/iOS 27/macOS 27 validation requires the separate Apple build environment. The Swift utility library itself is unchanged.

## Design and interaction policy

The main user interface remains this chat. Batch genuinely blocking questions and wait for their answers; do not repeat confirmed choices. Use concise owner/task/blocker/test/PR reports in ordinary messages. Documents and future native UI should follow the user's technical editorial references: warm paper, charcoal, restrained orange/cyan, strong typography and fine ruled grids.

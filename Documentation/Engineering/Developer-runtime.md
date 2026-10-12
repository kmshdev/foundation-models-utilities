# Developer runtime and phone control

The application and bridge implementation are Swift. This is an operational guide for the implemented runtime, not a claim that an external host or tunnel is already running.

## Mac execution

1. Build EngineeringStudioMac with Xcode 27 / Swift 6.4. Use the native ChatGPT account settings to sign in and choose an available subscription model. No OpenAI API key is required.
2. Clone `https://github.com/kmshdev/foundation-models-utilities` and keep its `origin` pointing at this approved fork. Select this folder in Developer Runtime; do not select an unrelated repository.
3. Install the official standalone native Codex executable and select that binary. Shell/Node wrappers are rejected. The app copies the explicitly selected native executable into its own sandbox container before launching it. This execution host requirement is separate from model authentication, which is implemented directly on both Apple platforms.
4. Connect developers. Eight actual app-server conversations provide presence. Roles in configuration alone do not count as connected or available.
5. Prepare an outcome's plan. New plans run automatically while connected; an existing saved plan has a Run Team action. Worktrees, receipts and interrupted work persist in Application Support.

App-owned Git commands set the bot identity `Engineering Studio <engineering-studio@localhost>` for that invocation and disable signing, hooks and fsmonitor. Dependency authors are preserved; global/repository Git settings are never changed. This allows scoped commits even when the app container has no user Git identity.

App Sandbox uses user-selected read/write access and app-scoped bookmarks for the clone. The chosen CLI's security scope is held while it is copied. Git worktrees and model/session state live in the app container. Native Mac execution under a signed sandboxed distribution still needs operational validation with that user's installed CLI and build tools.

## GitHub and Linear credentials

The chat's connectors can read and update project data during this development session. They do not copy credentials into a separately installed app.

- Public GitHub repository/PR/workflow reads need no token. To publish real developer commits and draft PRs, enter a fine-grained GitHub token scoped to `kmshdev/foundation-models-utilities`, with **Contents: Read and write** and **Pull requests: Read and write** (also **Workflows: write** when a task changes workflow files), in the host app's Connections. No GitHub administration permission is required. The host keeps this token in Keychain and never sends it to developer shells or the phone.
- Enter a Linear personal API key authorized for the ENG team and Engineering Workflow Automation project in Connections to import and publish tasks. The app verifies the fixed project and keeps the key in Keychain. A create reserves its UUID durably before sending and reconciles the same UUID after a lost response.
- These are app settings. **Do not add personal ChatGPT tokens, GitHub tokens or Linear keys to repository Actions secrets for this runtime.** Native builds and the current validation workflows do not need them.

Observed command receipts show exits and output. Developer acceptance claims are labeled as reported. Immutable commit/tree checks establish what is being published. The app never turns a claimed test count into a passing result or creates a fake PR link. Automatic draft publication only runs on fresh observed host completions when its GitHub credential is configured; reloaded history never triggers publication.

## Cloudflare Tunnel and Access

In Developer Runtime on the host, enable runtime sharing. The native server binds only `http://127.0.0.1:16080`. It uses an independently generated 256-bit pairing secret and has no routes for fetching account tokens or running arbitrary commands.

Configure a remotely managed Cloudflare Tunnel on this same host, with an HTTPS hostname routed to that loopback origin. Use a dedicated Access self-hosted application and a Service Auth policy restricted to a service token. Install `cloudflared` on the host and run the tunnel with its token supplied through its private token file. The tunnel token belongs only on that host; never commit it. A running Mac app alone does not start a Cloudflare connector.

On the iPhone, open Developer Runtime → Connect to a shared runtime and enter:

- the tunnel's HTTPS root address;
- the host's pairing code;
- the Access service token's client ID and secret if an Access policy protects the route.

The app stores pairing/Access credentials in the phone's Keychain. Requests use fixed `/v1/execution` routes, bounded sizes and timeouts, and do not follow redirects or submit account credentials to Cloudflare's login page. Publishing has a longer bounded budget because GitHub requires multiple object/ref/PR operations. Pausing developers preserves the bridge so the phone can restart them.

The Cloudflare connector was successfully inspected on 2026-10-12: the authorized account has active zones, but no existing Engineering Studio runtime tunnel/application. No Cloudflare API token is needed from the user to continue infrastructure configuration in this chat. A working deployment needs the selected active execution host and a tunnel connector running there; a nonexistent host cannot be repaired with a repository secret. Existing unrelated tunnels and Access applications were left intact.

## Recovery

A stopped or disconnected process marks uncertain turns as interrupted and retains their worktree, thread, turn and command receipts. Restart the runtime and Resume the existing task after inspecting its result. A repeated dispatch with identical task IDs does not create another delivery; changed tasks using already-delivered IDs are rejected.

Draft PR publication verifies parent lineage and file scope before creating remote objects. A single verified published ancestor supplies a stacked PR base. Multiple unpublished ancestors require a verified integration base; they are never silently flattened into a PR containing someone else's files. Stable branch and PR identity let retries reconcile lost responses. Existing unrelated branch changes, closed PRs and mismatched receipts remain explicit errors. Confirmed PR receipts are saved independently of worker connection state.

## Primary sources

- [OpenAI: app-owned ChatGPT tokens with Codex](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
- [OpenAI: direct inference and limitations](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Apple: sandbox file access and execution locations](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Apple: security-scoped access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())
- [Cloudflare: remotely managed tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)
- [Cloudflare: Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/)

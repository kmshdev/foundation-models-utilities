# Evidence and next work

Recorded 2026-10-12. The native application, model integration and developer runtime are implemented; build, launch, account entitlement and deployment evidence remain distinct.

## Current repository

The default app branch is `main`, tracking `origin/main`. The old local utilities-only branch is preserved as `archived-utilities-main`. CI watches `main`. The user's SDK 27 and harness updates are incorporated. No GitHub administration token is needed.

## Implemented and verified

- Direct Swift ChatGPT OAuth/PKCE registration, issued client IDs, validated RS256 identity, protected native Keychain profiles and serialized rotating refresh. No Node/Mac authentication service and no billed API-key substitute. Portable authentication checks and native CryptoKit/Security/loopback checks passed.
- Account catalog and bounded Responses SSE transport, terminal failure handling, local history and a real Foundation Models `LanguageModel` adapter. Native `LanguageModelSession` text/history/guided-plan checks passed. The store supports separate disabled, on-device and ChatGPT planning providers; stale/canceled plans do not publish.
- At `daf4a86`, [both production builds and 70 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38186560532) passed, and [the actual framework, auth, store and service checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38186560579) passed.
- At `1c45116`, [complete production launch validation](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38187099715) passed: actual Mac app and iOS 27 simulator app launched, the iPhone process survived and both screenshots were captured. Native evidence is in `Documentation/NativeBuild`. Initial phone-toolbar discoverability was subsequently corrected in `3fc7e4b`.
- GitHub fixed-repository reads, Linear fixed-project intake/publication, protected credentials, durable reserved Linear UUIDs and lost-response reconciliation are implemented. Public GitHub reads were exercised live; tests do not create throwaway production issues or PRs.
- Eight real Codex app-server conversations provide observed presence. Swift coordination reserves task identities atomically, leases non-overlapping paths, uses isolated worktrees and transfers confirmed ancestor context/commits. Actual commands, results, paths, commits and blockers are retained. Uncertain delivery never blindly repeats; saved threads/worktrees support resume.
- Account/model transitions await local executor shutdown. A phone account change does not stop an independent shared host. Model availability is gated during transitions. Remote pairing uses secure base64URL tokens, native Keychain and separate Cloudflare Access credentials.
- Swift HTTPS client and IPv4 loopback server implement snapshot, dispatch, cancel, resume, stop, restart and draft PR publication. Strict framing, limits, credentials, deadlines and no redirects protect the fixed routes. Only task identity crosses the publication bridge; model/GitHub credentials stay on the host.
- Git Data draft publication verifies immutable committed bytes, modes, owned paths and ancestry; stable branches and receipt recovery prevent duplicate PRs and unrelated overwrites. A single published ancestor supplies a stacked PR base. Composite unpublished bases return a concrete integration blocker. Confirmed local/remote commit receipts persist independently of connection state.
- The recovery fix preserves never-delivered reservation identities and automatically unblocks their dependency chains only after all ancestors complete. Uncertain delivery and failed persistence remain protected. Planning receives actual availability, prior assignments, commands, commits and blockers instead of repeating completed requirements.
- The final **118 Swift 6.4 core tests**, full native builds and both production launches passed in [38189015980](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38189015980) at `2b280cb`. The actual phone screenshot confirms New Outcome and More on its first screen. Normal builds [38188981683](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38188981683) and native regressions/captures [38188916037](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38188916037) also passed. Current captures and exact process/commit evidence are saved in `Documentation/NativeBuild` and `Documentation/Previews`.
- App-owned Git commands no longer require a user identity in the app container or interactive signing/hooks/fsmonitor. Invocation-only bot identity and safe command settings preserve repository/global configuration and dependency authors. A real Git regression verified this with absent identity and failing hooks/signing configured; [Both full native builds and 118 core tests](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38189784070), plus [native regression checks](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38189784128), passed at final application source commit `b79f343`.

## Operational validation still needing real setup

1. Sign into the installed app with the personal ChatGPT account. Browser consent, actual entitlement/inference, iPhone foreground loopback behavior and complete live developer turns cannot be established with injected account fixtures.
2. Select the approved local clone and a standalone native Codex binary on the execution host. App Sandbox requires the selected binary to be copied into its container; selected repository access uses read/write bookmarks. Signed sandboxed CLI/build-tool operation needs that host's actual environment.
3. Add a repository-scoped GitHub Contents/Pull requests write token and authorized Linear key to the host app's native Connections for operational mutations. They are app Keychain settings, not repository Actions secrets. The chat's connectors remain available without asking the user for new development tokens.
4. For phone remote execution, run the host, enable its loopback bridge and run a Cloudflare Tunnel connector on that host. The authorized Cloudflare account/zones were read successfully; no existing Engineering Studio route was found and unrelated infrastructure was not modified. A useful deployment requires an actual host, not another account token.
5. Complete signed physical-device distribution, accessibility interaction and any additional multimodal product scope.

Use [Developer runtime](../Documentation/Engineering/Developer-runtime.md) for exact credentials and host setup. These operational prerequisites do not block implementation, native build checks, deterministic framework tests or completing code fixes.

## Development agent setup

The requested Agency profiles, Codex skills, Interfaces plugin and curated strategy are installed. Twenty-four development profiles are distinct from the app's eight runtime specialists. Installation does not imply bot execution. Follow the runbook matching the next concrete outcome, serialize shared-file edits and use actual receipts for claims.

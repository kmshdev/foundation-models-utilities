# Native provider authorization

Delivery plan and researched API decisions, 2026-10-13. The implementation branch is `codex/provider-oauth-mcp`, based on the reviewed and merged PR #2 (`f94c972`). Live browser consent belongs to the account owner; native fixtures do not establish a live grant.

## Behavior

Connections provides native GitHub and Linear browser sign-in for their official read-only MCP endpoints. A successful connection reports protocol initialization and catalog discovery. It does not claim to have verified a provider user identity, repository installation or project access, and it does not activate unreviewed tools. The existing repository/project API connections and deterministic publication receipts remain separate.

GitHub uses a registered GitHub App, state and S256 PKCE, with the exact callback `engineeringstudio://oauth/github`. Configure its client ID and client secret in the native registration sheet; the secret is stored in this device's Keychain. No registration secret or user token belongs in Git or Actions secrets. GitHub's documented native public-client model requires the registration secret for exchange/refresh; protected device storage does not make that secret confidential in a distributed application. A Swift confidential broker remains an optional deployment choice.

Linear discovers the read-only protected resource and its authorization server, registers a public native client and requests only `read`. Its callback is an actual ephemeral IPv4 loopback listener. The app binds the listener before registering that exact callback. macOS opens the user's browser; iOS retains a system authentication browser until the listener completes or the user cancels. The current `Callback` API handles GitHub's custom scheme; it has no loopback case. An associated HTTPS callback is a separate deployment option requiring an owned domain, app entitlement and association file, not a prerequisite introduced here.

Restore reads protected records without opening a browser. Explicit Connect permits interactive consent; Refresh may rotate an existing token silently but cannot open a browser. Cancel closes the active browser/listener and invalidates the attempt. Disconnect closes MCP and removes its local grant; it is not a claim of remote revocation. Legacy publication credentials remain untouched.

## Layer and ownership plan

| Packet | Owner | Exclusive paths | Acceptance |
| --- | --- | --- | --- |
| P1: OAuth services | MCP/Apple implementation agent | `Services/EngineeringMCP/Authorization`, new native browser/Keychain files under `Services/StudioServices/ProviderOAuth`, new portable OAuth tests | Fixed issuer/endpoints, fresh PKCE/state, exact callbacks, persisted client binding, safe rotating refresh, cancellation and storage failures |
| P2: Connection lifecycle | Workflow implementation agent | Observable `ProviderMCPConnection`/phase/receipt files, `StudioWorkflows/ServiceConnections.swift` | Storage-only restore, interactive connect, silent refresh, truthful MCP status, fenced cancellation, preservation of legacy API behavior |
| P3: Native UI | Integration feature agent | `Features/IntegrationFeature` | Grouped native form, item-driven registration sheet, SF Symbols, accessible status and actionable errors, intent-colored controls |
| Integration and verification | Root | Manifest, app composition, documentation, native harness and CI | Layer checks, native lifecycle fixtures, SDK 27 builds and original plus authorization captures |

Read-only exploration preceded this plan. Dependent workers consume the explicit service contract; shared manifests and harness edits stay with root. Review independently before publication, return concrete defects to the owner and rerun affected checks after fixes.

## Authorization contract

An app-owned Swift actor owns one provider/local grant slot, its browser transaction, registration and token record. Its vault operations throw and save complete records atomically. A token snapshot supplies the SDK transport without accessing Keychain or presenting a browser inside an MCP request deadline. The actor serializes refresh and fences canceled/disconnected work, including credential commits. Public receipts contain metadata, never codes, secrets or tokens.

Every callback must match the exact scheme, host, port and path of the active attempt. Reject fragments, user info, duplicate authorization parameters, mismatched state or issuer and obsolete attempts. The OAuth HTTP transport does not follow redirects. Discovery and resource audiences are constrained to the official provider. Granted scopes are checked against the selected policy; a challenge cannot widen consent.

The pinned MCP Swift SDK remains **0.12.1** for transport, negotiation, catalogs and reviewed read operations. Its OAuth implementation rejects custom schemes and does not restore DCR client registration into a fresh authorizer reliably. Its synchronous, nonthrowing `TokenStorage` contract also cannot report a failed Keychain save. These are reasons for the small app-owned OAuth lifecycle, not for vendoring or replacing the SDK. No unrestricted discovered tool is attached to a Foundation Models session. The subscription planner continues to use `.toolCallingMode(.disallowed)`.

## Research findings

Primary documentation was refreshed with Firecrawl on 2026-10-13. Unauthenticated discovery reads performed that morning are research, not consent or registration. Linear's exact read-only resource metadata identifies `https://mcp.linear.app/mcp/readonly` with `read`; its unauthenticated challenge nevertheless advertises `read write`. The app requests `read` explicitly and reports a rejected scope without escalating it.

MCP authorization requires HTTPS or a localhost callback; it does not authorize arbitrary custom-scheme DCR redirects. GitHub's ordinary provider authorization documents non-HTTP callbacks, so its custom callback uses app-owned OAuth before passing the token to MCP. Linear MCP grants stay in a dedicated namespace: documentation permits direct Linear API/OAuth credentials at MCP, but does not establish the reverse audience relationship for MCP tokens at GraphQL.

GitHub App permissions come from installation and user access, rather than OAuth App `repo` scopes. Use GitHub App `offline_access` for expiring user tokens; an empty returned scope is valid for GitHub App tokens. No app private key is requested or shipped. Linear DCR records native application type, no client secret and the exact allocated callback; refresh uses the same saved client ID as the grant.

## Primary sources

- [Apple web authentication](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [custom callback](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/customscheme(_:)), [associated HTTPS callback](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)).
- [GitHub App native-client guidance](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app), [user-token exchange and non-HTTP callbacks](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app), [refresh](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens), [callback registration](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/about-the-user-authorization-callback-url).
- [Linear MCP](https://linear.app/docs/mcp), [direct OAuth](https://linear.app/developers/oauth-2-0-authentication), [authorization metadata](https://mcp.linear.app/.well-known/oauth-authorization-server), [read-only resource metadata](https://mcp.linear.app/.well-known/oauth-protected-resource/mcp/readonly).
- [Current MCP redirect security](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/security-considerations#communication-security), [native registration](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration#application-type-and-redirect-uri-constraints), [pinned Swift SDK](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1).

## Validation

The integrated Swift 6.4 run passed 128 system-test definitions (the live Codex handshake remains opt-in) and 31 portable MCP/OAuth tests, including 10 new authorization tests. These cover callback/issuer validation, native DCR payload, read-only grants, saved-client refresh, omitted refresh-token retention, cancellation fences and provider failures. Independent source review found and fixed missing native registration metadata and malformed issuer handling.

The Apple validation workflow builds both SDK 27 application targets and runs native MCP/OAuth fixtures. The capture harness additionally exercises the actual SDK S256 helper, isolated Keychain records and IPv4 listener; it covers lifecycle races and preservation of legacy API credentials before rendering the original seven workspace previews and two new connection/registration screens. Exact run results belong to the implementation PR's checks and description; pending checks must not be represented as passed.

Native browser, callback, vault and lifecycle fixtures are not live provider consent. An owner-provided GitHub App registration and actual account consent are required to establish a live GitHub grant; Linear DCR happens only on explicit Connect. No production registration, account authorization or token exchange was performed by research or fixtures.

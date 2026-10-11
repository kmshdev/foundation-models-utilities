# Personal ChatGPT access: supported Swift path

Research checkpoint, 2026-10-11. This is an implementation contract, not a claim that sign-in is already working in Engineering Studio.

OpenAI documents direct OAuth and HTTP/SSE Sign in with ChatGPT protocols for open-source local and self-hosted software. Implementing those language-independent protocols in Swift is our engineering choice; a personal Mac runner, Node authentication service or Codex subprocess is not a protocol requirement. The DevKit supplies an optional Node SDK and example app. Subscription access must not be replaced with a separately billed API key. The documented plan-sharing route is currently a preview.

## Registration and sign-in

1. Persist a stable `urn:uuid:<UUID>` host identity per installation/runtime. Start a loopback listener before opening the browser.
2. Authorize at `https://auth.openai.com/api/accounts/authorize`. Initial `client_id` is `dynamic_agent_client`; subsequent sign-ins use the issued client ID. Initial registration supplies `agent_name_hint=Engineering Studio`. Include `ext_agent_host_id`, `response_type=code`, fresh state and nonce, PKCE S256 challenge, and the exact redirect `http://127.0.0.1:<port>/auth/callback`.
3. Request scopes `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` and resource `https://api.openai.com/v1`. The literal loopback address matters; `localhost` is not interchangeable.
4. Validate callback state and errors. New registration must supply the issued client ID; an existing registration must not silently accept a different client ID.
5. Exchange the code at `https://auth.openai.com/api/accounts/oauth/token` with form fields `grant_type=authorization_code`, issued `client_id`, `code`, `code_verifier`, exact `redirect_uri` and `resource`. No client secret or API key is required.
6. Validate ID-token signature against OpenAI's published JWKS, issuer, audience against the issued client ID, expiry and nonce; require `chatgpt.tokens.use.direct` in the returned granted scopes before inference. Keep registrations separate by issued client ID and verified identity, even when emails match. Keychain is our Apple-platform storage choice for the protected registration/token bundle; never copy tokens into workspace JSON.
7. Serialize refresh operations per registration. POST to the same token endpoint with `grant_type=refresh_token`, issued `client_id`, saved `refresh_token` and `resource=https://api.openai.com/v1`; omit `scope`. Atomically replace access and rotating refresh tokens together. Preserve credentials on temporary network failures; terminal refresh errors require reauthorization using the saved client ID.

## Model access

Use OAuth Bearer authorization for `GET https://api.openai.com/v1/models`. This subscription path returns a `models` collection. Show entries whose visibility is `list`, display `display_name`, and submit the selected model's `slug`.

Use `POST https://api.openai.com/v1/responses` with the selected slug, input, `store: false` and `stream: true`. Accumulate SSE `response.output_text.delta`; success requires `response.completed`. Failed, incomplete, interrupted and usage-limit endings must remain visible even after some text arrived. Retain conversation history locally. Do not send unsupported fields such as `previous_response_id`, `temperature`, `top_p`, `max_output_tokens` or `metadata` on this path.

Hosted MCP/connectors and `tool_search` are not supported by this preview. Function/custom tools must be grouped in namespaces or supplied through `additional_tools` input items. Our integration will execute GitHub and Linear tools through Swift clients or a connected Swift execution runtime. As a project requirement, the Foundation Models adapter must implement `LanguageModel` and preserve session/model error distinctions; the existing chat-completions adapter is not a substitute for the Responses transport.

## Platform and hosting boundaries

The documented OSS callback is HTTP loopback. Apple's `ASWebAuthenticationSession.Callback` documents custom-scheme and associated-domain HTTPS callbacks; that does not establish an HTTP-loopback callback for the iPhone browser session. A Swift Network-framework listener/browser experiment on a real iPhone is needed to verify foreground/background lifecycle behavior. Do not invent a custom-scheme callback accepted by OpenAI. This experiment does not block portable registration, token, catalog, streaming or model-adapter implementation.

For an authorized self-hosted VM, follow OpenAI's secure registration-transfer flow with a distinct host identity and let the VM own refresh rotation. This is not Mac-specific. A paid or third-party remotely hosted product has a different onboarding path; do not assume OSS permission covers every deployment. Cloudflare remains a preference only where the runtime and this Swift implementation fit.

Codex App Server offers a separate managed ChatGPT device-code login: `account/login/start` with `type: "chatgptDeviceCode"` returns a verification URL and one-time code. This is distinct from app-owned SIWC OAuth tokens. OpenAI also documents passing an app-owned SIWC access token to a Codex child process configured for Responses over HTTP/SSE, communicating with that process over stdio and restarting it after token renewal. The direct app-server WebSocket transport is explicitly experimental and unsupported for production. The installed `codex-cli 0.159.0-alpha.3` generated schema labels `chatgptAuthTokens` internal-only, despite broader wording in the web guide; do not use it. Do not add unused Codex protocol codecs as a stand-in for implementing direct access.

## Primary references

- [Open-source token sharing overview](https://developers.openai.com/siwc/token-sharing-open-source)
- [Sign-in protocol](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Profiles, sessions and refresh](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)
- [Self-hosted VMs](https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms)
- [Codex App Server alternative](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
- [Codex managed authentication and transport](https://learn.chatgpt.com/docs/app-server)
- [Token fields and lifetimes](https://developers.openai.com/siwc/token-sharing-open-source/token-reference)
- [Apple web authentication callbacks](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback)
- [OpenAI DevKit source](https://github.com/openai/sign-in-with-chatgpt-devkit/tree/0a36fefeb913055c8c7a1a29b63d82b96b2e841a)

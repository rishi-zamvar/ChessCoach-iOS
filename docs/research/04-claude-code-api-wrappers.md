# 04: Claude Code / Agent SDK HTTP wrappers (subscription auth)

Researched 2026-10-15. Repo metadata comes from the GitHub API, and source claims come from shallow clones of each repo's default/main branch. Policy text is quoted from Anthropic's pages as fetched today.

Target: a personal iOS chess app talks to a home Windows 11 PC (Python) over Tailscale. It needs SSE streaming, a custom chess MCP server (Stockfish tools), no file or shell tools, and low latency.

---

## 1. Policy first (read before picking anything)

### 1.1 Current primary-source text

**Claude Code docs, Legal and compliance > Authentication and credential use** (code.claude.com/docs/en/legal-and-compliance):

> "**OAuth authentication** is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications."

> "**Developers** building products or services that interact with Claude's capabilities, including those using the Agent SDK, should use API key authentication through Claude Console or a supported cloud provider. Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow."

> "Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription..."

> "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK."

> "Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice."

**Agent SDK overview** (code.claude.com/docs/en/agent-sdk/overview):

> "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead."

The page also says use of the Agent SDK "is governed by Anthropic's Commercial Terms of Service".

**Consumer Terms** (effective Oct 8 2025, anthropic.com/legal/consumer-terms), prohibited uses:

> "Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise."

**Support article "Use the Claude Agent SDK with your Claude plan"** (support.claude.com/en/articles/15036540):

> "Update October 7, 2026: Claude Max and Team plans now include monthly API credits, which cover the Claude Agent SDK, `claude -p`, the Claude API, and Claude Managed Agents. You can still use the Claude Agent SDK, `claude -p`, and third-party apps with your subscription limits."

> "Update June 15, 2026: We've paused the previously-announced changes to Claude Agent SDK usage. For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription limits."

**Support article "Monthly API credits for Max and Team plans"** (support.claude.com/en/articles/17154008):

- Max 5x gets $100 a month and Max 20x gets $200 a month. Pro is **not eligible**.
- You claim the credit by linking a Console org on claude.ai (Settings > Billing).
- The credit covers "The Claude API (Messages API and Message Batches API) ... Claude Managed Agents, The Claude Agent SDK".
- It does not roll over. Credits are used before any purchased credits. When they run out, "API requests stop until your next monthly credits arrive. Usage is never charged to your Claude plan."

**Authentication docs** (code.claude.com/docs/en/authentication):

- `claude setup-token` produces a **one-year** OAuth token, which you set as `CLAUDE_CODE_OAUTH_TOKEN`. It "requires a Pro, Max, Team, or Enterprise plan. It can only make model requests ... MCP servers you configure locally still work."
- `--bare` mode does **not** read `CLAUDE_CODE_OAUTH_TOKEN`.
- On Windows, the `/login` credentials live in `%USERPROFILE%\.claude\.credentials.json`.
- Auth precedence: `ANTHROPIC_API_KEY` beats `CLAUDE_CODE_OAUTH_TOKEN`, which beats `/login`.

### 1.2 Timeline, 2026 (from secondary press; treat as context)

- **Jan 9 2026:** server-side blocking began for subscription OAuth used by third-party clients. Thariq Shihipar (Anthropic) said: "Third-party harnesses using Claude subscriptions create problems for users and are prohibited by our Terms of Service" (The Register, Feb 20 2026).
- **Feb 19 2026:** the legal page was updated. At that time it read "Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service — including the Agent SDK — is not permitted". The **current** wording, quoted above, is softer. It no longer contains that sentence, and it now names "ordinary, individual usage of Claude Code and the Agent SDK".
- **Apr 4 2026:** third-party harnesses, starting with OpenClaw, stopped being covered by subscription limits and moved to "extra usage" billing (Boris Cherny, via TechRadar and Hongkiat).
- **May 13 2026:** Anthropic announced that from Jun 15, Agent SDK and `claude -p` would move to a separate metered credit. On **Jun 15** that change was paused.
- **Oct 7 2026:** Max and Team plans got monthly API credits. Subscription limits still apply to SDK and `claude -p` use.

### 1.3 Conservative reading for this project

- **Lowest risk:** a Console **API key** from the org linked to the Max plan's monthly API credit ($100 or $200 a month). Agent SDK and API use under an API key is explicitly allowed. A chess coach uses a tiny fraction of $100 a month. The catch is that this needs **Max**, not Pro.
- **Grey zone (currently tolerated, single user):** the unmodified `claude` binary, driven by the Agent SDK on your own PC with your own login or `setup-token`. You are the only end user, and the Oct 7 support text says SDK and `claude -p` use "still draw[s] from your subscription limits". It is still an automated, non-human path. The consumer terms ban that "except ... where we otherwise explicitly permit it". The support article arguably is that permission, but Anthropic has changed this three times in 2026 and enforces "without prior notice". Expect possible future breakage.
- **Do not do:** any proxy that pulls the OAuth token out of the binary and calls `api.anthropic.com` directly while spoofing Claude Code headers. That covers ccproxy's `claude_api` plugin, auth2api, and similar tools. This is exactly "intermediate Claude.ai credentials or session tokens" and is the pattern the Jan and Apr enforcement targeted. Multi-account pooling is worse still.

---

## 2. Candidates

Two projects named "claude-code-proxy" are **out of scope**: 1rgs/claude-code-proxy (3.8k stars) and fuergaosi233/claude-code-proxy (2.8k stars). Both go the *opposite* direction, running Claude Code against OpenAI or other models.

| Repo | Stars | Last push | License | Lang | Engine |
|---|---|---|---|---|---|
| [RichardAtCT/claude-code-openai-wrapper](https://github.com/RichardAtCT/claude-code-openai-wrapper) | 625 | 2026-09-24 | MIT (pyproject; no LICENSE file, so GitHub shows none) | Python | Agent SDK `query()` |
| [codingworkflow/claude-code-api](https://github.com/codingworkflow/claude-code-api) | 333 | 2026-06-25 | GPL-3.0 | Python | raw `claude -p` subprocess |
| [CaddyGlow/ccproxy-api](https://github.com/CaddyGlow/ccproxy-api) | 275 | 2026-10-07 | MIT | Python | Agent SDK (`ClaudeSDKClient` pool) **or** direct OAuth HTTP |
| [mazamaka/claudegate](https://github.com/mazamaka/claudegate) | 12 | 2026-10-13 | MIT | Python | Agent SDK `ClaudeSDKClient` (warm) |
| [aweussom/agentry](https://github.com/aweussom/agentry) | 7 | 2026-10-07 | MIT | Python | persistent `claude -p` stream-json |
| [AmazingAng/auth2api](https://github.com/AmazingAng/auth2api) | 582 | 2026-07-01 | none | TS | direct OAuth token to API (**avoid**) |
| [cabinlab/claude-code-api](https://github.com/cabinlab/claude-code-api) | 28 | 2025-08-17 | none | TS | stale |
| [MehdiMohseni82/claude-code-proxy](https://github.com/MehdiMohseni82/claude-code-proxy) | 2 | 2026-09-23 | none | TS | Agent SDK; tiny |
| claude-max-api-proxy (npm, atalovesyou) | n/a (GitHub repo 404) | — | — | JS | spawns CLI per request |

### 2.1 RichardAtCT/claude-code-openai-wrapper

Gotcha: the GitHub *default* branch is a stale Actions branch from 2025-07. The real code is on `main` at v2.3.0, pinned to `claude-agent-sdk ^0.2.159`.

- **Auth:** auto-detects from `ANTHROPIC_API_KEY`, Bedrock, Vertex, or CLI login. Because the CLI does the auth, `CLAUDE_CODE_OAUTH_TOKEN` also works. The README has a "Terms Compliance" section that recommends an API key.
- **API:** OpenAI `/v1/chat/completions` and Anthropic `/v1/messages`, plus `/v1/models` and `/v1/sessions*`.
- **Streaming:** SSE, yes.
- **Sessions:** a `session_id` extra_body field. Server memory keeps history with a 1-hour TTL, and the SDK `resume` is used.
- **Process:** `query()` per request, so it **spawns a fresh CLI per request**. No warm process.
- **MCP:** **effectively no.** It has `/v1/mcp/*` endpoints and an `mcp_client.py`, but `mcp_servers` is never passed to `ClaudeAgentOptions`. I grepped for it. The README's own roadmap still lists "MCP integration" as unchecked.
- **Tools:** disabled by default. You can opt in with `enable_tools`, allowed/disallowed lists, or `x-claude-*` headers.
- **Windows:** claims cross-platform. Docker is provided.
- **Concurrency:** one process per request, with a rate limiter.
- **Verdict:** the most popular option, but it lacks server-side MCP and is cold per request.

### 2.2 codingworkflow/claude-code-api

- **Auth:** CLI login.
- **API:** OpenAI chat, plus sessions and projects.
- **Streaming:** SSE.
- **Process:** a subprocess per session, `claude -p ... --output-format stream-json --dangerously-skip-permissions`. All built-in tools are enabled with permissions bypassed.
- **MCP:** none.
- **Windows:** has `start.bat`, but the README says it "may require WSL".
- **Concurrency:** max 10 sessions.
- **License:** GPL-3.
- **Verdict:** reject. It is effectively a remote shell, with no tool restriction and no MCP.

### 2.3 CaddyGlow/ccproxy-api

- **Shape:** a plugin-based multi-provider proxy (Claude, Codex, Copilot). It exposes OpenAI Chat, OpenAI Responses, and Anthropic Messages, all with streaming.
- **`claude_sdk` plugin:** uses `ClaudeSDKClient` with an optional session pool (`session_pool_size = 5`, TTL 3600). `ClaudeAgentOptions` are configurable, including `mcp_servers`, but by default it injects its own "confirmation" MCP permission server.
- **`claude_api` plugin:** `auth_type = "oauth"`. It sends the subscription OAuth token straight to the API with merged `anthropic-beta` headers and has a `credential_balancer`. That is the prohibited pattern.
- **Weight:** heavy (DuckDB analytics, dashboard, metrics).
- **Windows:** not documented.
- **Verdict:** capable, but too much surface, and the default path invites the risky mode.

### 2.4 mazamaka/claudegate (best off-the-shelf fit)

Built on FastAPI and the Agent SDK. It is young, with 12 stars and created 2026-08, but well engineered.

- **Auth:** CLI login or `CLAUDE_CODE_OAUTH_TOKEN`. `claudegate doctor` recommends `claude setup-token` for services. `ANTHROPIC_API_KEY` also works.
- **API:** OpenAI `/v1/chat/completions` with SSE streaming, tool calling, images and PDFs, reasoning output, `/metrics`, and `/health`.
- **Sessions:** **warm** `ClaudeSDKClient` per conversation (`LiveSession`). Follow-ups send only the new messages. Idle TTL is 1800 s. If a session is reaped, it is rebuilt from request history.
- **Tools:** `CLAUDEGATE_BARE_MODE=true` is the default. The request's system prompt replaces Claude Code's, and built-in tools are removed (`options["tools"] = <request tools only>`, `strict_mcp_config=True`). Watch out: `permission_mode` defaults to `bypassPermissions`. Non-loopback binds refuse to start without `CLAUDEGATE_API_KEY`.
- **MCP:** the tools are **client-declared** OpenAI functions, bridged through an in-process MCP server. The model's tool call is returned to the *client*, which runs it and posts the result back. There is no config for attaching your own server-side MCP server, such as Stockfish on the PC. You would have to fork it, or run the tool loop in a middle layer.
- **Windows:** CI runs the hermetic suite on Windows. You must point `CLAUDEGATE_CLI_PATH` at native `claude.exe`, because the SDK refuses the npm `claude.cmd` shim. It needs a ProactorEventLoop, which `serve` sets up. Use NSSM or Task Scheduler as the service runner.
- **Concurrency:** `CLAUDEGATE_MAX_SESSIONS=64`, about 200 MB of RAM per live CLI process.

### 2.5 aweussom/agentry

- Persistent `claude -p` stream-json worker launched with `--safe-mode --strict-mcp-config --tools "" --no-session-persistence`. It clears the conversation between requests, so it is stateless.
- OpenAI API, Windows `start.ps1`.
- **No MCP**, by design ("reverse MCP").
- **Useful latency data** (their benchmark, Sep 2026, on a trivial prompt): a fresh CLI process took a 1.5 to 1.7 s median, versus **0.88 s** for a warm reset plus turn. Built-in context dropped from about 14.1k to about 3.7k input tokens with the lean flags.

### 2.6 AmazingAng/auth2api, claude-max-api-proxy, and similar

- auth2api takes the OAuth token and calls the API directly, with multi-account pools.
- claude-max-api-proxy spawns the CLI per request and was marketed for OpenClaw, the first harness Anthropic cut off.
- Avoid both on policy grounds, and in auth2api's case for credential handling too.

---

## 3. Feature matrix against requirements

| Need | RichardAtCT | claudegate | ccproxy (sdk) | agentry | Custom FastAPI + Agent SDK |
|---|---|---|---|---|---|
| SSE streaming | yes | yes | yes | yes | yes (`include_partial_messages`) |
| Server-side custom MCP (Stockfish) | **no** | no (client tools only) | config possible | no | **yes** (`create_sdk_mcp_server`, in-process) |
| No file/shell tools | default off | bare mode | configurable | `--tools ""` | `tools=[]` + `strict_mcp_config` |
| Warm process | no | **yes** | pool | yes | yes (`ClaudeSDKClient`) |
| Windows | claimed | CI + caveats | undocumented | yes | yes (native `claude.exe`) |
| Subscription auth | yes | yes | yes | yes | yes |
| Size/complexity | medium | medium | heavy | small | ~150 LOC |

---

## 4. Recommendation

**Build a thin custom FastAPI service over `claude-agent-sdk`.** No existing wrapper attaches a *server-side* MCP server, which is the one hard requirement. claudegate is the closest, and its source is a good reference for the Windows and warm-session details. Sketch:

- `ClaudeAgentOptions` settings:
  - `tools=[]`, which removes every built-in tool (Bash, Edit, Read, Web*).
  - `mcp_servers={"chess": create_sdk_mcp_server(...)}`, an in-process server: `@tool` functions wrapping python-chess plus a long-lived Stockfish UCI process.
  - `allowed_tools=["mcp__chess__*"]` (list them explicitly), `strict_mcp_config=True`, `setting_sources=[]`, and `permission_mode="dontAsk"` so nothing outside the allowlist runs.
  - `system_prompt=<coach prompt>`, which replaces the Claude Code preset so the context stays small.
  - `include_partial_messages=True` for token streaming. Also set `max_turns`, `cwd=<empty temp dir>`, and `cli_path=<native claude.exe>`.
- **Warm sessions:** one `ClaudeSDKClient` per game or conversation, kept in a dict with an idle TTL. That gives roughly 1 s first-token latency instead of a cold spawn every time. Re-create the client with `resume=<session_id>` after it is reaped.
- **Endpoint:** a single `POST /chat` that streams `text/event-stream` (FastAPI `StreamingResponse`). An OpenAI-compatible shape is unnecessary because you write the iOS client yourself.
- **Hosting:** bind to the Tailscale IP only and add a bearer token anyway. Run under NSSM on Windows, with the ProactorEventLoop that uvicorn uses by default on Windows.
- **Auth, in preference order:**
  1. An `ANTHROPIC_API_KEY` from the Console org linked to the Max monthly API credit. This is explicitly permitted, free within $100 or $200 a month, and immune to subscription-policy churn.
  2. `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` (1-year expiry, renew annually). This is the grey zone: single-user use of the unmodified binary is currently tolerated and draws from subscription limits. Never extract that token and call the API directly.

**Simplification worth considering:** with zero built-in tools and API-key auth, the Agent SDK adds little. The plain `anthropic` Python SDK (Messages API, `stream=True`, and the tool runner calling Stockfish functions directly) does the same job without the CLI subprocess (about 200 MB of RAM per session, plus the Windows `.cmd`/exe gotchas), and with lower latency. Pick the Agent SDK only if you must stay on subscription OAuth.

---

## Sources

- https://code.claude.com/docs/en/legal-and-compliance
- https://code.claude.com/docs/en/agent-sdk/overview
- https://code.claude.com/docs/en/agent-sdk/python
- https://code.claude.com/docs/en/authentication
- https://www.anthropic.com/legal/consumer-terms
- https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan
- https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans
- https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan
- https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546
- https://www.techradar.com/pro/bad-news-claude-users-anthropic-says-youll-need-to-pay-to-use-openclaw-now
- https://www.hongkiat.com/blog/anthropic-closed-openclaw-loophole/
- https://thenewstack.io/anthropic-pauses-claude-agent-sdk-subscription-change/
- The GitHub repos linked in section 2. Source claims were verified by grepping shallow clones.

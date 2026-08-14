---
name: easy-deploy
description: Deploy a local web project to production on the user's own accounts (Cloudflare Pages/Workers, Vercel, Neon, EdgeOne). Handles static sites, SPAs (Vite/Astro), Next.js, small Node APIs, and databases. Use when the user asks to deploy, publish, ship, go live, 部署, 上线, or 发布 a website or web app.
---

# easy-deploy

Deploy the project in front of you to production, on the **user's own accounts**, preferring free tiers. You orchestrate existing official CLIs (`wrangler`, `vercel`) — this skill tells you which one, in what order, and what to check.

## Workflow

Follow these five steps in order. Do not skip the confirmation step.

### 1. Preflight

Run the detection script from the project root:

```bash
bash <skill-dir>/scripts/preflight.sh .
```

It reports: project type, framework, package manager, build command, database hints, which CLIs are installed, and which accounts are logged in. If it reports **candidate sub-projects**, the deployable app lives in a subdirectory (docs/monorepo layout) — re-run preflight there and treat that subdirectory as the project root for every later step. If the script is unavailable, inspect `package.json`, config files (`next.config.*`, `vite.config.*`, `astro.config.*`, `wrangler.toml`/`wrangler.jsonc`), and lockfiles manually.

**Log in here, not later.** Step 3 has to name the account the deploy will go to,
and `whoami` is the only way to know it. Run `bash <skill-dir>/scripts/login.sh
cloudflare` now if preflight reports not-logged-in: it opens a browser tab and
polls until the credential lands, so the pipeline continues the moment the user
clicks approve. Tell the user a tab is waiting — the link expires in ~2 minutes.

**Then check the account can actually host this.** A first-ever deploy on a fresh
account hits one-time setup steps that no CLI can perform, and they fail late:
without a workers.dev subdomain, `wrangler deploy` uploads the Worker and *then*
errors with no URL. Preflight reports these once logged in. Collect every one
into a **single** message with dashboard links — the user should make one trip,
not one per wall. Details in `references/cloudflare.md`.

### 2. Choose a platform

| Project type | Target | Why |
|---|---|---|
| Pure static (`index.html`, no build step) | Cloudflare Pages | Free, unlimited bandwidth, instant |
| SPA / static build (Vite, CRA, Astro static) | Cloudflare Pages | Same as above; build locally, upload `dist/` |
| Next.js (SSR, app router, API routes) | Vercel | First-party support, zero config |
| **Next.js + a Cloudflare adapter** (`vinext`, `@opennextjs/cloudflare`, `@cloudflare/vite-plugin`) | **Cloudflare Workers** | The app is written against Workers APIs and D1/R2 bindings. Vercel would split it from its database |
| Small API / server (Hono, Express-lite) | Cloudflare Workers | Free tier; port to Workers if trivial, else Vercel serverless |
| Long-running server, WebSocket, Docker | Fly.io or Railway | Out of core scope — see `references/` note below, confirm with user |
| Needs SQL database | Neon (Postgres) or Cloudflare D1 (SQLite) | See `references/databases.md` |

Framework is a hint, not a verdict. When preflight finds an **existing deploy config** (a `deploy` script in package.json, `DEPLOY.md`, wrangler/vercel config, platform adapter deps), read it and follow the project's own deploy path; use the table only when there is none.

**A project that already runs somewhere is not choosing a platform — it is paying
a migration cost.** The table is written for new projects. For an existing app,
the question is not "which database is better" but "what does moving cost":
count the coupling first (imports of a runtime module like `cloudflare:workers`,
call sites using a platform-specific client, storage bindings) and say the number
out loud. An app with a few hundred raw D1 calls does not "just move to
Supabase"; a hundred-line one might. Recommend the cheapest target that solves
the user's actual complaint, which is often the same platform on their own
account rather than a different platform.

Special case: if the user's audience is in mainland China, read `references/china-access.md` **before** choosing — platform subdomains like `*.vercel.app` are often unreachable there.

Load the matching reference for exact commands:
- `references/cloudflare.md` — Pages, Workers, D1, custom domains
- `references/vercel.md` — deploy, env vars, domains
- `references/databases.md` — Neon, D1, Supabase, Turso; how to pick
- `references/china-access.md` — mainland China reachability, EdgeOne, ICP 备案

### 3. Confirm with the user

Deployment is outward-facing and publishes content to the internet. Before deploying, state in one short block and wait for approval:

- Platform and account (from `whoami` output)
- Project/site name and the URL it will get
- Build command and output directory
- Env vars / secrets that will be set (names only, never values)
- Expected cost (should normally be "free tier") — and **whether a payment method
  is required anyway**. Cloudflare R2 wants a card on file even when usage is
  free. A confirmation that says "free" followed by a credit-card wall reads as a
  bait and switch.
- **Whether the app is safe to expose.** A deploy puts it at a public URL with no
  gate in front. Look for authentication — a login route, a session or auth
  dependency, a middleware check. If there is none, say so plainly: anyone with
  the URL gets whatever the app does, including spending API credits the user is
  paying for. Offer a gate (Cloudflare Access, basic auth at the edge) or
  deploying without the expensive secrets set, and let the user choose. Do not
  silently publish an unauthenticated admin tool.

Exception: if the user already said "deploy it, don't ask" or this is a re-deploy of the same project to the same target, proceed directly.

### 4. Execute

1. **Build locally first.** Run the build command and fix errors before touching the platform. Never debug a build through repeated cloud deploys.
2. Login already happened in step 1. On headless/SSH machines where the browser flow is impossible, use `CLOUDFLARE_API_TOKEN` / `VERCEL_TOKEN` env vars instead.
3. Provision the database first if one is needed, so its connection string can be set as a secret before the app deploys.
4. Deploy with the platform CLI (exact commands in the references).
5. Set env vars as platform secrets. **Never** commit `.env` to git or bake secrets into build output.

### 5. Verify and report

- `curl -sI <url>` — expect HTTP 200 (or 3xx to a working page). For SPAs also check a deep route returns the app, not 404.
- **Retry before believing a failure.** On a first-ever deploy the certificate may
  still be provisioning, and a rollout can take a moment to reach every edge, so
  the first request or two can fail at the TLS layer (`curl` exit 35, code `000`)
  or answer from the previous version. Poll a few times with a short sleep. A
  deploy that printed a URL and a version id has already succeeded; do not
  redeploy to "fix" it.
- If the site needs a database, hit one route that touches it — and read the
  body, not just the status. A route can answer 200 from cache or a stub while
  the binding is broken.
- If you set any secret, confirm it exists on the platform rather than assuming
  the write succeeded.
- If a gate was added, verify both directions: the protected paths reject without
  credentials, and accept with them.
- Report to the user: live URL, platform dashboard link, how to bind a custom domain (one-liner, details in references), and how to re-deploy (`the exact command`).

## Rules

- User's accounts, user's ownership. Never create accounts, never store credentials outside the platform CLI's own auth.
- Free tier by default. Anything that can bill money (paid plans, usage-based resources beyond free quotas) requires explicit user approval.
- Don't touch DNS the user didn't ask about. Custom domain setup is opt-in.
- If the project has an existing deploy config (`vercel.json`, `wrangler.toml`, `netlify.toml`, a `deploy` script, `DEPLOY.md`, CI workflow), respect it — ask before switching platforms.
- One deploy attempt may fail on first-time setup (missing project, missing binding). Read the error, fix the cause, retry once or twice; if still failing, report the exact error instead of thrashing.

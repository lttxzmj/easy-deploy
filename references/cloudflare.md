# Cloudflare: Pages, Workers, D1, R2

Auth: `npx wrangler login` (opens browser). Check: `npx wrangler whoami`.

## First deploy on a new account — do this before anything else

A Cloudflare account that has never hosted a Worker is missing two things that
**no CLI can create**. Both are one-time, both need the dashboard, and both fail
late and confusingly if you skip them.

Check for them during preflight and give the user **one** message with every
item they need to click, not one interruption per wall.

| What | Where | Needed for | If missing |
|---|---|---|---|
| workers.dev subdomain | `dash.cloudflare.com/<account-id>/workers/onboarding` | any Worker URL | `wrangler deploy` uploads the Worker, then errors with no URL |
| R2 enabled | `dash.cloudflare.com/<account-id>/r2` | object storage only | `wrangler r2 bucket create` fails `[code: 10042]` |

Get `<account-id>` from `wrangler whoami` and keep it — you need it to build
these links, and the user cannot find the pages easily without them.

**workers.dev subdomain.** One text field: lowercase letters, digits, hyphens.
Globally unique across all of Cloudflare, and effectively permanent (changing it
is a support ticket). It is account-wide, so tell the user to pick a personal or
org handle, not this project's name — every future Worker lives under it as
`<worker>.<subdomain>.workers.dev`. Free plan; no payment details.

**R2.** Requires a payment method on file even though the free tier (10 GB, 1M
Class A ops, 10M Class B ops, zero egress) costs nothing. Say this explicitly:
"free tier" in a confirmation block, followed by a credit-card wall, reads as a
bait and switch. If the user refuses, R2 is the only thing blocked — offer to
deploy without object storage and note which features go dark.

## Pages — static sites and SPA builds

First deploy (creates the project automatically):

```bash
npm run build                          # or the detected build command
npx wrangler pages deploy <output-dir> --project-name=<name>
```

- `<output-dir>`: `dist/` (Vite/Astro), `build/` (CRA), or `.` for plain static.
- `<name>` becomes the URL: `https://<name>.pages.dev`. Lowercase, hyphens only.
- Re-deploy = run the same command again.

SPA routing: if deep links 404, add a `_redirects` file to the output dir:

```
/* /index.html 200
```

Env vars for the **build** happen locally (they're baked in at build time — so anything in a `VITE_*`/`NEXT_PUBLIC_*` var is public; never put secrets there).

## Workers — small APIs (Hono is ideal)

Two shapes. Check which one you have before writing any config.

### Hand-written config

Needs a `wrangler.toml` (or `wrangler.jsonc`):

```toml
name = "<name>"
main = "src/index.ts"
compatibility_date = "2025-01-01"
```

```bash
npx wrangler deploy                    # → https://<name>.<account>.workers.dev
npx wrangler secret put SOME_KEY       # secrets, prompts for value
npx wrangler tail                      # live logs when debugging
```

### Adapter-generated config — do not write a wrangler.toml

When the project uses `@cloudflare/vite-plugin`, `vinext`, or
`@opennextjs/cloudflare`, the build **generates** the config (typically
`dist/server/wrangler.json`) from the framework config. Adding a `wrangler.toml`
by hand creates a second, ignored source of truth.

```bash
npm run build
npx wrangler deploy -c dist/server/wrangler.json
```

Resource ids cannot be pasted into a generated file — the next build overwrites
it. Find where the plugin reads its bindings (in Vite projects, the `config`
option passed to `cloudflare()`), and make the ids come from the environment:

```ts
database_id: process.env.CF_D1_DATABASE_ID || "<placeholder>",
```

```bash
CF_D1_DATABASE_ID=... npm run build && npx wrangler deploy -c dist/server/wrangler.json
```

Verify before deploying — one line, and it catches a whole class of mistakes:

```bash
node -e 'const c=require("./dist/server/wrangler.json");console.log(c.d1_databases,c.r2_buckets)'
```

Express does not run on Workers directly. If the server is a thin Express app (a few routes), porting to Hono is usually <30 min; otherwise use Vercel serverless or ask the user about Fly.io/Railway.

## D1 — SQLite on Workers

```bash
npx wrangler d1 create <db-name>
npx wrangler d1 execute <db-name> --remote --file=schema.sql
```

**Do not paste the printed block verbatim.** `d1 create` suggests a binding named
after the database (`byline-production` → `binding: "byline_production"`), but the
binding name is what the code reads — usually `env.DB`. Match the code, not the
suggestion, or the Worker deploys cleanly and then throws on its first query.
Same for R2 and `env.FILES`.

Many apps create their own tables at runtime (`CREATE TABLE IF NOT EXISTS` on
first request). Check before hunting for a schema file — an empty database is a
valid starting state for those, and `d1 execute` is unnecessary.

Access in code via the binding. Only works from Workers/Pages Functions — not
reachable from Vercel or external servers.

## R2 — object storage on Workers

Enable it in the dashboard first (see the top of this file), then:

```bash
npx wrangler r2 bucket create <bucket-name>
npx wrangler r2 bucket list
```

Bound as `env.FILES` (or whatever the code uses) and accessed with
`.put()` / `.get()` / `.delete()`. Like D1, reachable only from Workers.

No egress charges, which is why it is the right default for user uploads and
generated images on this platform.

## Custom domain

CLI support is limited; use the dashboard: **Workers & Pages → project → Custom domains → Set up a domain**. If the domain's DNS is already on Cloudflare it's one click; otherwise the dashboard shows the CNAME to add. Tell the user these steps — don't change their DNS yourself.

## Gotchas

- **A brand-new workers.dev subdomain fails TLS for the first ~30–60s** while the
  certificate provisions. `curl` returns `000` and exit code 35, right after a
  deploy that printed a URL and a version id — it looks exactly like a broken
  deploy and is not. Retry with backoff before concluding anything. Do not
  redeploy; it changes nothing and wastes the user's time.
- **Right after a deploy, different paths can briefly answer from different
  versions** while the rollout propagates. If one route shows old behaviour and
  another shows new, wait and re-check before debugging code that is already
  correct.
- **Every `wrangler` subcommand needs to know the Worker name**, and for adapter
  projects there is no `wrangler.toml` to read it from. `wrangler secret put`,
  `secret list` and `tail` all fail with `Required Worker name missing` unless
  you pass the generated config:

  ```bash
  npx wrangler secret put MY_KEY -c dist/server/wrangler.json
  npx wrangler secret list      -c dist/server/wrangler.json   # verify it landed
  ```

  Worth doing the `secret list` check every time: when the `put` is piped rather
  than typed, its error scrolls past and the secret is silently never set. The
  app then deploys fine and fails at runtime on a missing variable.
- **`wrangler deploy` can "succeed" and still leave you with nothing.** With no
  workers.dev subdomain it uploads the Worker, prints `Uploaded <name>`, then
  asks whether to register a subdomain — and in a non-interactive shell answers
  its own question with "no" and exits non-zero. Read the tail of the output, not
  the word "Uploaded".
- `wrangler whoami` exits 0 even when **not** authenticated — never trust the exit code, check the output for "logged in".
- `wrangler login` waits only ~2 minutes for the browser approval, then kills its callback server (clicking Allow after that does nothing). In detached shells its "opening browser" step can silently fail. Use `scripts/login.sh cloudflare`, which extracts the OAuth URL, opens it explicitly, and polls — and warn the user the link is fresh for ~2 minutes.
- Unauthenticated `wrangler d1 create` in a non-TTY shell reports a misleading "set CLOUDFLARE_API_TOKEN" error — the actual problem is usually just the missing login above.

- First `wrangler login` on a headless machine: use `CLOUDFLARE_API_TOKEN` env var instead (user creates token at dash.cloudflare.com/profile/api-tokens, template "Edit Cloudflare Workers").
- Pages project names are global per-account; "project already exists" on first deploy means pick another name or it was created earlier — check `npx wrangler pages project list`.
- Free tier: Pages unlimited static requests; Workers 100k requests/day. Plenty for vibe-coded projects.

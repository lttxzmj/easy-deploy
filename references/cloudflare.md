# Cloudflare: Pages, Workers, D1

Auth: `npx wrangler login` (opens browser). Check: `npx wrangler whoami`.

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

Express does not run on Workers directly. If the server is a thin Express app (a few routes), porting to Hono is usually <30 min; otherwise use Vercel serverless or ask the user about Fly.io/Railway.

## D1 — SQLite on Workers

```bash
npx wrangler d1 create <db-name>
# copy the printed [[d1_databases]] block into wrangler.toml
npx wrangler d1 execute <db-name> --remote --file=schema.sql
```

Access in code via the `env.DB` binding. Only works from Workers/Pages Functions — not reachable from Vercel or external servers.

## Custom domain

CLI support is limited; use the dashboard: **Workers & Pages → project → Custom domains → Set up a domain**. If the domain's DNS is already on Cloudflare it's one click; otherwise the dashboard shows the CNAME to add. Tell the user these steps — don't change their DNS yourself.

## Gotchas

- `wrangler whoami` exits 0 even when **not** authenticated — never trust the exit code, check the output for "logged in".
- `wrangler login` waits only ~2 minutes for the browser approval, then kills its callback server (clicking Allow after that does nothing). In detached shells its "opening browser" step can silently fail. Use `scripts/login.sh cloudflare`, which extracts the OAuth URL, opens it explicitly, and polls — and warn the user the link is fresh for ~2 minutes.
- Unauthenticated `wrangler d1 create` in a non-TTY shell reports a misleading "set CLOUDFLARE_API_TOKEN" error — the actual problem is usually just the missing login above.

- First `wrangler login` on a headless machine: use `CLOUDFLARE_API_TOKEN` env var instead (user creates token at dash.cloudflare.com/profile/api-tokens, template "Edit Cloudflare Workers").
- Pages project names are global per-account; "project already exists" on first deploy means pick another name or it was created earlier — check `npx wrangler pages project list`.
- Free tier: Pages unlimited static requests; Workers 100k requests/day. Plenty for vibe-coded projects.

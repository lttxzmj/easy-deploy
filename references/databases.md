# Databases — pick the smallest thing that works

Decision order for a typical vibe-coded project:

1. **No real persistence needed** (demo, portfolio, landing page) → no database. localStorage or a JSON file is fine; say so instead of provisioning one.
2. **Deploying to Cloudflare Workers/Pages** → **D1** (SQLite, same platform, zero extra accounts). See `cloudflare.md`.
3. **Deploying to Vercel, needs SQL** → **Neon** (serverless Postgres, free tier, works with Prisma/Drizzle out of the box).
4. **Project needs auth / file storage / realtime** → **Supabase** (Postgres + auth + storage in one; heavier, but replaces three services).
5. Turso (hosted SQLite over HTTP) is a fine alternative to Neon for tiny apps if the user already uses it.

## Neon

Dashboard flow is simplest: user creates a project at console.neon.tech → copy the connection string. CLI alternative:

```bash
npx neonctl auth
npx neonctl projects create --name <name>
npx neonctl connection-string
```

Then set it as a platform secret (never in code, never in a committed `.env`):

```bash
npx vercel env add DATABASE_URL production      # Vercel
npx wrangler secret put DATABASE_URL            # Workers (use Neon's HTTP driver @neondatabase/serverless)
```

Free tier: ~0.5 GB storage, auto-suspends when idle (first query after idle takes ~1s — normal, warn the user, not a bug).

## Supabase

User creates the project at supabase.com (CLI project creation requires org setup — dashboard is faster). You need two values: `SUPABASE_URL` and the `anon` key (safe for browsers; the `service_role` key is server-only, treat as a secret). Apply schema with `npx supabase db push` if the project has migrations, otherwise via the dashboard SQL editor.

## Migrations / schema

- Prisma detected → `npx prisma migrate deploy` (or `db push` for toy projects) against the new DATABASE_URL.
- Drizzle detected → `npx drizzle-kit push`.
- Raw SQL files → run via `psql`, Neon dashboard SQL editor, or `wrangler d1 execute`.

Always run schema setup **before** first deploy verification, or the "verify a DB route" step will fail for the wrong reason.

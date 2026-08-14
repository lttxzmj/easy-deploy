# Databases — pick the smallest thing that works

**First: is this actually a decision?** The list below is for a project that has
no database yet. A project that already has one has already chosen, usually in
hundreds of call sites, and the question becomes migration cost rather than
preference. Count before recommending anything:

```bash
grep -rc "\.prepare(\|prisma\.\|db\.query\|supabase\.from" --include=*.ts --include=*.js src app 2>/dev/null | grep -v :0
```

A few hundred raw platform-specific calls is a rewrite, not a switch — say the
number out loud and let the user decide. Note also that on Workers the runtime
and the database are coupled: D1 and R2 are reachable only through bindings, so
"move the database to Supabase" quietly means "move off Workers too, or add an
HTTP driver". Recommend the change that fixes the user's actual complaint; more
often than not that is the same stack on an account they own.

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

A dependency in `package.json` is not evidence that the ORM is used. Confirm it
has call sites before running its migration tool — projects routinely carry a
drizzle or prisma dependency that nothing imports, and pushing that schema
creates tables the app will never read while the ones it needs stay missing.

```bash
grep -rl "drizzle-orm\|@prisma/client" --include=*.ts --include=*.js src app 2>/dev/null | head
```

- Prisma, and it is imported → `npx prisma migrate deploy` (or `db push` for toy projects) against the new DATABASE_URL.
- Drizzle, and it is imported → `npx drizzle-kit push`.
- Raw SQL files → run via `psql`, Neon dashboard SQL editor, or `wrangler d1 execute`.
- **No migration step at all** → many small apps run `CREATE TABLE IF NOT EXISTS`
  on first request. An empty database is then the correct starting state; load
  one page and the schema appears. Check for this before hunting for a schema
  file that does not exist.

Always run schema setup **before** first deploy verification, or the "verify a DB route" step will fail for the wrong reason.

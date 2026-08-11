# Vercel — Next.js and serverless

Auth: `npx vercel login` (email or browser). Check: `npx vercel whoami`.

## Deploy

From the project root:

```bash
npx vercel --prod --yes
```

- `--yes` accepts defaults non-interactively: creates/links the project, name = directory name.
- Vercel builds **in the cloud** — but still run `npm run build` locally first to catch errors cheaply.
- First deploy writes `.vercel/` (project link). Add `.vercel` to `.gitignore`.
- URL: `https://<project>-<hash>-<team>.vercel.app` plus the stable `https://<project>.vercel.app`.

Preview deploy (shareable, not production): `npx vercel` without `--prod`.

## Env vars

```bash
npx vercel env add DATABASE_URL production      # prompts for value
npx vercel --prod --yes                          # re-deploy to apply
```

Bulk-import from a local file: `npx vercel env pull` / or loop over `.env` lines with `vercel env add`. Never print secret values into the chat or commit them.

`NEXT_PUBLIC_*` vars are baked into client JS — public by definition; secrets must not use that prefix.

## Custom domain

```bash
npx vercel domains add <domain.com>
```

Prints the DNS records (A / CNAME) the user must add at their DNS provider. Report those records to the user; don't modify their DNS.

## Scope notes

- Framework auto-detection covers Next.js, Astro, SvelteKit, Nuxt, Vite. For plain Vite/static, Cloudflare Pages is still the better default (bandwidth), but Vercel works if the user already lives there.
- A standalone `server.js` (Express) does **not** run as-is; Vercel wants serverless functions (`api/*.ts`) or a supported framework. Options: restructure into `api/` functions, or use Fly.io/Railway for a real server — ask the user.
- Free (Hobby) tier: personal/non-commercial, 100 GB bandwidth/month, serverless included. Commercial use technically requires Pro — mention this if the user's site is a business.
- Mainland China: `*.vercel.app` is unreliable/blocked there. See `china-access.md`.

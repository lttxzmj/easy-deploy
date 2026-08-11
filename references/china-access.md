# Mainland China reachability

Read this when the user's audience is in mainland China (常见信号：中文内容、用户明说"国内访问"、微信分享场景). Reachability from China changes over time — treat the notes below as defaults, and when in doubt tell the user to test from a mainland network or a site like boce.com / 17ce.com.

## The short version

- **Platform subdomains are the problem.** `*.vercel.app` is frequently blocked or unstable from mainland China; `*.pages.dev` and `*.workers.dev` are unreliable too. A deploy that "works" from overseas may be unreachable for the actual audience.
- **A custom domain fixes most of it.** The same Vercel/Cloudflare deployment on the user's own domain (not on the shared platform subdomain) is usually reachable, though latency is mediocre (no mainland PoPs without ICP filing).
- **Truly fast mainland access requires ICP 备案** — see below. This is out of scope for a quick deploy; set expectations honestly.

## Recommended options, in order

1. **Cloudflare Pages/Workers + custom domain** — best effort without any filing. Reachable in most regions, latency ~100–300 ms. Good default.
2. **Tencent EdgeOne Pages** (edgeone.ai / pages.edgeone.ai) — Pages-like static hosting from Tencent with a free tier and generally better mainland reachability even on its default domain. Deploy via its dashboard (connect Git repo) or `edgeone pages` CLI. Consider it when the user has no custom domain and the audience is primarily mainland.
3. **Vercel + custom domain** — acceptable, but tell the user reachability fluctuates. Never hand a mainland-facing user a bare `*.vercel.app` URL as the final result.

## ICP 备案 (filing) — what to tell the user

- Required only for hosting on **mainland servers/CDN nodes**. Overseas hosting (all options above) needs no filing.
- Filing requires a mainland-registered domain owner (individual with ID or a company), takes roughly 2–4 weeks, and is done through a mainland cloud provider (Aliyun/Tencent Cloud).
- Practical advice for a vibe-coded project: don't file. Use option 1 or 2. Only suggest filing if the user is building something long-term with a mainland audience and asks about speed.

## Domain notes

- Domains bought at overseas registrars (Cloudflare, Namecheap) work fine for options 1–3 and cannot be used for ICP filing without transferring; domains at Aliyun/Tencent work everywhere. Don't make the user move registrars for a quick deploy.
- `.dev` / `.app` TLDs force HTTPS (HSTS-preloaded) — fine on all platforms above, just don't suggest plain-HTTP setups with them.

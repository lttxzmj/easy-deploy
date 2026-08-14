#!/usr/bin/env bash
# easy-deploy preflight: detect project type, tooling, and account login status.
# Usage: preflight.sh [project-dir]   (defaults to current directory)
set -uo pipefail

dir="${1:-.}"
cd "$dir" 2>/dev/null || { echo "ERROR: cannot cd to '$dir'"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# `timeout` is GNU coreutils and is NOT on macOS, where most users of this skill
# are. Calling it directly made every guarded command fail, so account detection
# silently reported "NOT logged in" forever. Fall back to gtimeout, then to
# running the command unguarded -- a missing timeout is better than a wrong answer.
tmout() {
  local secs="$1"; shift
  if have timeout; then timeout "$secs" "$@"
  elif have gtimeout; then gtimeout "$secs" "$@"
  else "$@"
  fi
}
dep_in_pkg() { [ -f package.json ] && grep -qE "\"$1\"[[:space:]]*:" package.json; }

# CLIs like wrangler are often a local devDependency, not a global install.
cli_version() {
  if have "$1"; then "$1" --version 2>/dev/null | head -1
  elif [ -x "node_modules/.bin/$1" ]; then
    echo "$("node_modules/.bin/$1" --version 2>/dev/null | head -1) (local devDependency)"
  fi
}
run_cli() {
  if have "$1"; then "$@"
  elif [ -x "node_modules/.bin/$1" ]; then local c="$1"; shift; "node_modules/.bin/$c" "$@"
  else return 127; fi
}

echo "== project =="
echo "dir: $(pwd)"

framework="unknown"
build_cmd=""
output_dir=""

if [ -f package.json ]; then
  echo "package.json: yes"
  name=$(grep -m1 '"name"' package.json | sed 's/.*: *"\(.*\)".*/\1/')
  echo "name: ${name:-"(none)"}"

  if dep_in_pkg next; then
    framework="nextjs"; build_cmd="build (next build)"; output_dir=".next"
    if dep_in_pkg "@opennextjs/cloudflare" || dep_in_pkg "@cloudflare/vite-plugin" || dep_in_pkg vinext; then
      framework="nextjs-on-cloudflare"; build_cmd="build"; output_dir="dist"
      echo "NOTE: Next.js wired for Cloudflare Workers -- deploy with wrangler, NOT Vercel"
    fi
  elif dep_in_pkg nuxt; then
    framework="nuxt"; build_cmd="build"; output_dir=".output"
  elif dep_in_pkg astro; then
    framework="astro"; build_cmd="build"; output_dir="dist"
  elif dep_in_pkg vite; then
    framework="vite"; build_cmd="build"; output_dir="dist"
  elif dep_in_pkg react-scripts; then
    framework="cra"; build_cmd="build"; output_dir="build"
  elif dep_in_pkg hono; then
    framework="hono-server"
  elif dep_in_pkg express || dep_in_pkg fastify || dep_in_pkg koa; then
    framework="node-server"
  fi

  grep -q '"build"' package.json && echo "has-build-script: yes" || echo "has-build-script: no"

  # Not everything with a package.json and a build script is a website. Browser
  # extensions, CLIs, libraries and desktop apps all look identical to framework
  # detection, and "deploy it anyway" wastes a real deploy to produce something
  # nobody can open. Report the kind; let the agent stop and ask.
  kind=""
  if [ -f manifest.json ] && grep -q '"manifest_version"' manifest.json 2>/dev/null; then
    kind="browser-extension"
  elif [ -f public/manifest.json ] && grep -q '"manifest_version"' public/manifest.json 2>/dev/null; then
    kind="browser-extension"
  elif dep_in_pkg electron; then
    kind="desktop-app (electron)"
  elif dep_in_pkg react-native || dep_in_pkg expo; then
    kind="mobile-app"
  elif grep -qE '"bin"[[:space:]]*:' package.json; then
    kind="cli-tool"
  elif grep -qE '"(main|exports|module)"[[:space:]]*:' package.json && [ "$framework" = "unknown" ]; then
    kind="library (no framework detected)"
  fi
  [ -n "$kind" ] && echo "NOT-A-WEBSITE: $kind -- confirm with the user before deploying anything"
elif [ -f index.html ]; then
  framework="static"
  echo "package.json: no (index.html at root -> pure static)"
else
  echo "package.json: no, index.html: no at root"
  candidates=$(find . -maxdepth 3 \( -name node_modules -o -name .git \) -prune -o \
    \( -name package.json -o -name index.html \) -print 2>/dev/null \
    | sed 's|/[^/]*$||' | sort -u | head -10)
  if [ -n "$candidates" ]; then
    echo "candidate sub-projects found -- the app likely lives in one of these;"
    echo "re-run preflight against it and deploy from there:"
    echo "$candidates" | sed 's/^/  /'
  else
    echo "no package.json or index.html anywhere -- inspect manually"
  fi
fi

echo "framework: $framework"
[ -n "$build_cmd" ] && echo "build: npm run $build_cmd -> $output_dir/"

# Naming the framework is a means, not the end -- what decides the platform is
# what the build emits. Detection by dependency returns "unknown" for most real
# projects; an already-built output directory answers the same question without
# knowing the framework at all.
for candidate in dist build .output out public; do
  if [ -f "$candidate/index.html" ]; then
    echo "built-output: $candidate/ contains index.html -> servable as static"
    break
  elif [ -d "$candidate" ] && [ "$framework" = "unknown" ]; then
    echo "built-output: $candidate/ exists but has no index.html -- inspect before assuming static"
    break
  fi
done
if [ "$framework" = "unknown" ]; then
  echo "HINT: framework unknown -- run the build, then classify by what lands in the"
  echo "      output directory (index.html + assets => static host; a server entry => Workers/Vercel)."
fi

# package manager from lockfile
pm="npm"
[ -f pnpm-lock.yaml ] && pm="pnpm"
[ -f yarn.lock ] && pm="yarn"
{ [ -f bun.lockb ] || [ -f bun.lock ]; } && pm="bun"
echo "package-manager: $pm"

# database / backend hints
echo ""
echo "== database hints =="
for d in prisma drizzle-orm mongoose pg mysql2 better-sqlite3 @supabase/supabase-js; do
  dep_in_pkg "$d" && echo "dep: $d"
done
[ -d prisma ] && echo "dir: prisma/ (check schema.prisma datasource)"
# names only -- never print values. .dev.vars is where Workers projects keep their
# secrets locally, so omitting it misses every env name in a Cloudflare app.
grep -hsoE '^[A-Z0-9_]+' .env .env.local .env.production .dev.vars 2>/dev/null \
  | sort -u | sed 's/^/env-name: /'

# existing deploy config -- if anything shows up here, the project has already
# chosen its platform; read its docs and follow its path instead of the defaults
echo ""
echo "== existing deploy config =="
for f in wrangler.toml wrangler.jsonc vercel.json netlify.toml fly.toml Dockerfile \
         DEPLOY.md DEPLOYMENT.md docs/DEPLOY.md; do
  [ -f "$f" ] && echo "found: $f"
done
[ -d .github/workflows ] && echo "found: .github/workflows/"
if [ -f package.json ]; then
  grep -E '"(deploy|predeploy|release)[a-z:_-]*"[[:space:]]*:' package.json | sed 's/^[[:space:]]*/script: /'
  for d in wrangler vercel "@opennextjs/cloudflare" "@cloudflare/vite-plugin" vinext; do
    dep_in_pkg "$d" && echo "dep: $d"
  done
fi

echo ""
echo "== tooling =="
echo "node: $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
for c in wrangler vercel; do
  v=$(cli_version "$c")
  [ -n "$v" ] && echo "$c: $v" || echo "$c: NOT INSTALLED (npx $c works on demand)"
done

echo ""
echo "== accounts =="
# wrangler whoami exits 0 even when unauthenticated -- parse the output instead
cf_who=$(tmout 20 run_cli wrangler whoami 2>/dev/null)
if printf '%s' "$cf_who" | grep -q "logged in"; then
  echo "cloudflare: logged in"
  # Needed to build the dashboard links below. The account id is only ever shown
  # here, and the user cannot navigate to those pages without it.
  acct=$(printf '%s' "$cf_who" | grep -oE '[0-9a-f]{32}' | head -1)
  [ -n "$acct" ] && echo "cloudflare-account-id: $acct"

  # One-time account setup that no CLI can perform, and that fails late: with no
  # subdomain, `wrangler deploy` uploads the Worker and only then errors out
  # with no URL, having answered its own prompt with "no".
  echo ""
  echo "== cloudflare account bootstrap =="
  if tmout 20 run_cli wrangler r2 bucket list >/dev/null 2>&1; then
    echo "r2: enabled"
  else
    echo "r2: NOT enabled -- USER ACTION: dash.cloudflare.com/${acct:-<account-id>}/r2"
    echo "    wants a payment method even on the free tier; blocks object storage only"
  fi
  # No CLI command reports the subdomain, so this is advisory rather than a check.
  echo "workers.dev subdomain: not readable by CLI. If 'wrangler deploy' ends with"
  echo "    'register a workers.dev subdomain', USER ACTION:"
  echo "    dash.cloudflare.com/${acct:-<account-id>}/workers/onboarding"
  echo "    lowercase/digits/hyphens, globally unique, effectively permanent, and"
  echo "    account-wide -- pick a personal handle, not this project's name"
elif [ -n "$(cli_version wrangler)" ]; then
  echo "cloudflare: NOT logged in (run: scripts/login.sh cloudflare)"
fi
v=$(tmout 15 run_cli vercel whoami 2>/dev/null)
if [ -n "$v" ]; then
  echo "vercel: logged in as $v"
elif [ -n "$(cli_version vercel)" ]; then
  echo "vercel: NOT logged in (run: npx vercel login)"
fi

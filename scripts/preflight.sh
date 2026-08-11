#!/usr/bin/env bash
# easy-deploy preflight: detect project type, tooling, and account login status.
# Usage: preflight.sh [project-dir]   (defaults to current directory)
set -uo pipefail

dir="${1:-.}"
cd "$dir" 2>/dev/null || { echo "ERROR: cannot cd to '$dir'"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
dep_in_pkg() { [ -f package.json ] && grep -qE "\"$1\"[[:space:]]*:" package.json; }

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
elif [ -f index.html ]; then
  framework="static"
  echo "package.json: no (index.html at root -> pure static)"
else
  echo "package.json: no, index.html: no -- inspect manually"
fi

echo "framework: $framework"
[ -n "$build_cmd" ] && echo "build: npm run $build_cmd -> $output_dir/"

# package manager from lockfile
pm="npm"
[ -f pnpm-lock.yaml ] && pm="pnpm"
[ -f yarn.lock ] && pm="yarn"
[ -f bun.lockb ] || [ -f bun.lock ] && pm="bun"
echo "package-manager: $pm"

# database / backend hints
echo ""
echo "== database hints =="
for d in prisma drizzle-orm mongoose pg mysql2 better-sqlite3 @supabase/supabase-js; do
  dep_in_pkg "$d" && echo "dep: $d"
done
[ -d prisma ] && echo "dir: prisma/ (check schema.prisma datasource)"
if ls .env* >/dev/null 2>&1; then
  # names only -- never print values
  grep -hsoE '^[A-Z0-9_]+' .env .env.local .env.production 2>/dev/null | sort -u | sed 's/^/env-name: /'
fi

# existing deploy config
echo ""
echo "== existing deploy config =="
for f in wrangler.toml wrangler.jsonc vercel.json netlify.toml fly.toml Dockerfile; do
  [ -f "$f" ] && echo "found: $f"
done
[ -d .github/workflows ] && echo "found: .github/workflows/"

echo ""
echo "== tooling =="
for c in node wrangler vercel; do
  if have "$c"; then echo "$c: $("$c" --version 2>/dev/null | head -1)"; else echo "$c: NOT INSTALLED"; fi
done

echo ""
echo "== accounts =="
if have wrangler; then
  timeout 15 wrangler whoami >/dev/null 2>&1 && echo "cloudflare: logged in" || echo "cloudflare: NOT logged in (run: wrangler login)"
fi
if have vercel; then
  v=$(timeout 15 vercel whoami 2>/dev/null)
  [ -n "$v" ] && echo "vercel: logged in as $v" || echo "vercel: NOT logged in (run: vercel login)"
fi

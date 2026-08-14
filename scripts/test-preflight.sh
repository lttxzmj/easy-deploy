#!/usr/bin/env bash
# Fixture tests for preflight.sh.
#
# A skill is mostly prose, and prose cannot be tested. The two scripts can be,
# and they are where the silent failures live: account detection was broken on
# every Mac from the day it was written, because it called `timeout`, which is
# GNU coreutils and absent on macOS. It reported "NOT logged in" forever and
# looked correct on a logged-out machine. Ten lines of fixture would have caught
# it on the first run.
#
#   bash scripts/test-preflight.sh
#
# Each case builds a throwaway project shape and asserts on one line of output.
# Nothing here touches the network or any account.

set -uo pipefail
cd "$(dirname "$0")/.."
PREFLIGHT="$(pwd)/scripts/preflight.sh"

root="$(mktemp -d "${TMPDIR:-/tmp}/preflight-fixtures.XXXXXX")"
trap 'rm -rf "$root"' EXIT

pass=0
fail=0

# expect <name> <dir> <substring that must appear in the output>
expect() {
  local name="$1" dir="$2" needle="$3"
  local out
  out="$(bash "$PREFLIGHT" "$dir" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n       expected to find: %s\n' "$name" "$needle"
    printf '%s\n' "$out" | sed 's/^/       | /'
  fi
}

mk() { mkdir -p "$root/$1"; echo "$root/$1"; }

# --- framework detection ---------------------------------------------------
d="$(mk static)"; printf '<h1>hi</h1>' > "$d/index.html"
expect "bare index.html is static" "$d" "framework: static"

d="$(mk vite)"; printf '{"name":"v","devDependencies":{"vite":"^5"},"scripts":{"build":"vite build"}}' > "$d/package.json"
expect "vite detected" "$d" "framework: vite"

d="$(mk next)"; printf '{"name":"n","dependencies":{"next":"15"},"scripts":{"build":"next build"}}' > "$d/package.json"
expect "plain next detected" "$d" "framework: nextjs"

# The case that matters most: deploying this to Vercel splits it from its data.
d="$(mk next-cf)"; printf '{"name":"n","dependencies":{"next":"15"},"devDependencies":{"vinext":"0.0.50"},"scripts":{"build":"vinext build"}}' > "$d/package.json"
expect "next+adapter is Workers, not Vercel" "$d" "framework: nextjs-on-cloudflare"
expect "next+adapter warns explicitly" "$d" "NOT Vercel"

# --- things that are not websites ------------------------------------------
d="$(mk ext)"; printf '{"name":"e","scripts":{"build":"tsc"}}' > "$d/package.json"
printf '{"manifest_version":3,"name":"e"}' > "$d/manifest.json"
expect "browser extension flagged" "$d" "NOT-A-WEBSITE: browser-extension"

d="$(mk cli)"; printf '{"name":"c","bin":{"c":"./cli.js"},"scripts":{"build":"tsc"}}' > "$d/package.json"
expect "cli tool flagged" "$d" "NOT-A-WEBSITE: cli-tool"

d="$(mk lib)"; printf '{"name":"l","main":"./index.js","scripts":{"build":"tsc"}}' > "$d/package.json"
expect "library flagged" "$d" "NOT-A-WEBSITE: library"

d="$(mk desktop)"; printf '{"name":"d","devDependencies":{"electron":"30"},"scripts":{"build":"x"}}' > "$d/package.json"
expect "electron flagged" "$d" "NOT-A-WEBSITE: desktop-app"

# --- unknown framework, classified by what the build emits -----------------
d="$(mk unknown-static)"; printf '{"name":"u","scripts":{"build":"make"}}' > "$d/package.json"
mkdir -p "$d/dist"; printf '<h1>built</h1>' > "$d/dist/index.html"
expect "unknown framework falls back to output dir" "$d" "built-output: dist/ contains index.html"
expect "unknown framework gets guidance" "$d" "HINT: framework unknown"

# --- monorepo / wrong directory --------------------------------------------
d="$(mk mono)"; mkdir -p "$d/apps/web"
printf '{"name":"w","devDependencies":{"vite":"^5"}}' > "$d/apps/web/package.json"
expect "monorepo points at the sub-project" "$d" "candidate sub-projects found"

# --- secrets are named, never printed --------------------------------------
d="$(mk secrets)"; printf '{"name":"s","dependencies":{"next":"15"}}' > "$d/package.json"
printf 'AI_API_KEY=sk-or-v1-do-not-print-me\n' > "$d/.dev.vars"
expect ".dev.vars names are read" "$d" "env-name: AI_API_KEY"
out="$(bash "$PREFLIGHT" "$d" 2>&1)"
if printf '%s' "$out" | grep -qF "do-not-print-me"; then
  fail=$((fail + 1)); printf '  FAIL secret VALUE leaked into output\n'
else
  pass=$((pass + 1)); printf '  ok   secret values stay out of the output\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

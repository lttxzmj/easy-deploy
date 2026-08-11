#!/usr/bin/env bash
# easy-deploy login helper: drive a browser OAuth login without blocking the agent.
# Starts the platform's login flow in the background (a browser tab opens on the
# user's machine) and polls until the credential lands, then exits 0.
# Usage: login.sh cloudflare|vercel [timeout-seconds]   -- run from the project dir
set -uo pipefail

platform="${1:-cloudflare}"
timeout="${2:-180}"

# wrangler whoami exits 0 even when unauthenticated -- parse the output instead
cf_logged_in() {
  npx --no-install wrangler whoami 2>/dev/null | grep -q "logged in"
}

case "$platform" in
  cloudflare)
    if cf_logged_in; then
      echo "cloudflare: already logged in"
      exit 0
    fi
    log="$(mktemp "${TMPDIR:-/tmp}/wrangler-login.XXXXXX")"
    echo "cloudflare: starting OAuth flow (log: $log)"
    npx wrangler login >"$log" 2>&1 &
    login_pid=$!

    # wrangler claims to open the browser but that silently fails in detached
    # shells -- extract the URL and open it ourselves, and print it as fallback
    url=""
    for _ in 1 2 3 4 5 6; do
      sleep 2
      url="$(grep -m1 -oE 'https://dash\.cloudflare\.com/oauth2?/[^"[:space:]]+' "$log" 2>/dev/null || true)"
      [ -n "$url" ] && break
    done
    if [ -n "$url" ]; then
      echo "cloudflare: approve this in the browser (tab should open now):"
      echo "$url"
      if command -v open >/dev/null 2>&1; then open "$url"; elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url"; fi
    fi

    SECONDS=0
    while [ "$SECONDS" -lt "$timeout" ]; do
      if ! kill -0 "$login_pid" 2>/dev/null; then
        # wrangler exited: either success, or its own auth-code timeout
        break
      fi
      sleep 5
    done
    if cf_logged_in; then
      echo "cloudflare: login complete after ${SECONDS}s"
      exit 0
    fi
    kill "$login_pid" 2>/dev/null
    echo "cloudflare: login did not complete within ${SECONDS}s (wrangler's own"
    echo "authorization window also expires). Re-run this script to get a fresh"
    echo "OAuth link -- it exits 0 immediately once the credential exists."
    exit 1
    ;;
  vercel)
    if [ -n "$(npx vercel whoami 2>/dev/null)" ]; then
      echo "vercel: already logged in"
      exit 0
    fi
    echo "vercel: 'vercel login' needs an interactive terminal -- ask the user to"
    echo "run 'npx vercel login' themselves, or set VERCEL_TOKEN (created at"
    echo "vercel.com/account/tokens) for a headless setup."
    exit 1
    ;;
  *)
    echo "usage: login.sh cloudflare|vercel [timeout-seconds]"
    exit 2
    ;;
esac

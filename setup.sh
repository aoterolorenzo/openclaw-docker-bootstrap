#!/usr/bin/env bash
# OpenClaw Docker Bootstrap.
# Idempotent — safe to re-run. Each step is a no-op if already done.
set -euo pipefail

cd "$(dirname "$0")"

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Pre-flight: Docker available and running.
step "Checking Docker"
command -v docker >/dev/null 2>&1 \
    || err "Docker not found. Install Docker Desktop first: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 \
    || err "Docker daemon not running. Open Docker Desktop and try again."
echo "Docker OK"

# 2. Bootstrap .env from template.
if [[ ! -f .env ]]; then
    step "Creating .env from .env.example"
    cp .env.example .env
fi

# 3. Generate a unique gateway token if missing.
if grep -qE '^OPENCLAW_GATEWAY_TOKEN=$' .env; then
    step "Generating unique gateway token"
    token="$(openssl rand -hex 32)"
    # Portable in-place edit (works on both macOS BSD sed and GNU sed).
    awk -v t="$token" '
        /^OPENCLAW_GATEWAY_TOKEN=$/ { print "OPENCLAW_GATEWAY_TOKEN=" t; next }
        { print }
    ' .env > .env.tmp && mv .env.tmp .env
fi

# 4. Build the derived image with skill deps + brew shim.
step "Building derived image (first run ~3 min, cached after)"
docker compose build openclaw-gateway

# 5. Onboarding wizard (interactive: provider, API key, skills).
# Run via the gateway service with --no-deps and --entrypoint node so the
# gateway daemon does NOT start as a depends_on side-effect of using
# openclaw-cli. With the daemon running on empty config it exits with
# "Missing config" and `restart: unless-stopped` loops it; because the cli
# shares the gateway's network namespace via network_mode, every restart
# disrupts in-flight DNS lookups inside the wizard (EAI_AGAIN on npm).
# This is the pattern documented in upstream docs/install/docker.md
# ("Manual flow") for setup-time operations.
step "Running onboarding wizard"
echo "(You'll be prompted for an LLM provider and API key.)"
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js onboard --mode local --no-install-daemon

# 6. Doctor --fix to install bundled plugin runtime deps.
step "Installing bundled plugin runtime deps (doctor --fix)"
docker compose run --rm openclaw-cli doctor --fix || \
    echo "(doctor reported issues; review the output above. Continuing.)"

# 7. Start the gateway with fresh config.
step "Starting gateway"
docker compose up -d --force-recreate openclaw-gateway

# 8. Wait for healthz.
step "Waiting for gateway to become healthy"
for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null http://127.0.0.1:18789/healthz 2>/dev/null; then
        echo "Gateway healthy"
        break
    fi
    sleep 1
done

# 9. Print the access info.
token="$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d= -f2-)"
cat <<INFO

============================================================
OpenClaw is running.

Web UI (token included in fragment, auto-login):
    http://127.0.0.1:18789/#token=$token

Files you can edit on your host filesystem:
    ./config/openclaw.json         main config
    ./openclaw-workspace/skills/   installed skills (markdown manifests)
    ./openclaw-workspace/agents/   agent state + memory

Common commands:
    docker compose logs -f openclaw-gateway   # live logs
    docker compose restart openclaw-gateway   # reload after editing config
    docker compose down                       # stop everything
    docker compose up -d openclaw-gateway     # start again

If the browser asks for device pairing, approve it from a terminal:
    docker compose run --rm openclaw-cli devices list
    docker compose run --rm openclaw-cli devices approve <request-id>
============================================================
INFO

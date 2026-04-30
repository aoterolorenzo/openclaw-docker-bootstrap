#!/usr/bin/env bash
# OpenClaw Docker Bootstrap — upgrade to the latest upstream.
# Refreshes:
#   1. docker-compose.yml from openclaw/openclaw main
#   2. alpine/openclaw base image (Docker Hub)
#   3. The derived openclaw-with-deps:local image (rebuilt FROM the new base)
#   4. The running gateway container (force-recreated on the new image)
#
# Idempotent: re-running with no upstream changes is a no-op (cached layers).
set -euo pipefail

cd "$(dirname "$0")"

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || err "Docker not found."
docker info >/dev/null 2>&1 || err "Docker daemon not running."

# 1. Refresh docker-compose.yml from upstream (does not touch the override
#    or the Dockerfile).
step "Refreshing docker-compose.yml from openclaw/openclaw"
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/openclaw/openclaw/main/docker-compose.yml -o "$tmp"
if [[ -f docker-compose.yml ]] && cmp -s docker-compose.yml "$tmp"; then
    echo "docker-compose.yml is already up to date."
    rm -f "$tmp"
else
    mv "$tmp" docker-compose.yml
    echo "docker-compose.yml updated."
fi

# 2 + 3. Pull the latest alpine/openclaw and rebuild the derived image on
#    top of it. --pull forces Docker to re-resolve the FROM tag instead of
#    reusing the cached layer.
step "Rebuilding openclaw-with-deps:local on the latest alpine/openclaw"
docker compose build --pull openclaw-gateway

# 4. Recreate the gateway container so it runs on the new image.
step "Recreating gateway"
docker compose up -d --force-recreate openclaw-gateway

# 5. Wait for healthz before declaring victory.
step "Waiting for gateway to become healthy"
for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null http://127.0.0.1:18789/healthz 2>/dev/null; then
        echo "Gateway healthy."
        break
    fi
    sleep 1
done

# 6. Print the version that is now running.
step "Done"
docker compose run --rm openclaw-cli --version 2>/dev/null || true

cat <<'INFO'

If you have outstanding bundled plugin runtime deps after the upgrade
(usually flagged in the gateway logs), refresh them with:

    docker compose run --rm openclaw-cli doctor --fix
    docker compose restart openclaw-gateway
INFO

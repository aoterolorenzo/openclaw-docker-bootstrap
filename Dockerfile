# Derived from the published alpine/openclaw image (Debian 12 underneath).
# Adds the native deps the Linux skills installer expects from brew but cannot
# install itself, plus a brew shim and pre-installed npm globals so the
# upstream onboarding wizard succeeds end-to-end on Linux/Docker.
FROM alpine/openclaw

USER root

# Native deps for brew-kind skills (tmux, ffmpeg/video-frames) + curl/CA for
# the uv install.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tmux \
        ffmpeg \
        ca-certificates \
        curl \
 && rm -rf /var/lib/apt/lists/*

# uv (Astral) — used by Python skills like nano-pdf. The installer DOES check
# hasBinary("uv") before falling back to brew, so this alone unlocks uv skills.
RUN curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR=/usr/local/bin sh

# Pre-install the npm-based skill packages globally so the onboarding wizard
# can register them without depending on the cli container's flaky DNS
# (Docker forbids `dns:` next to `network_mode: "service:..."`, which leaves
# the cli with Docker Desktop's internal resolver and the EAI_AGAIN errors
# we saw during onboarding). Pre-installing removes the network dependency.
#
# @steipete/summarize is the Linux-friendly install of the `summarize` skill;
# upstream's SKILL.md only knows the macOS brew formula (steipete/tap/summarize)
# but summarize.sh also publishes the same binary on npm.
RUN npm install -g \
        mcporter \
        clawhub \
        @steipete/summarize

# Fake brew shim. The upstream skills installer for `kind: "brew"` does:
#     if (spec.kind === "brew" && !brewExe) return brewMissingFailure;
# with no `hasBinary(formula)` short-circuit. So even though `tmux`/`ffmpeg`
# are already in /usr/bin via apt and `summarize` is in the npm global bin,
# the installer fails "brew not installed". This shim satisfies the lookup:
#   - `brew --prefix` → /usr (so installer resolves /usr/bin as brew bin dir)
#   - `brew install ...` → exit 0 (binaries already present from apt + npm)
#   - everything else → exit 0
COPY --chmod=755 <<'EOF' /usr/local/bin/brew
#!/bin/sh
case "$1" in
    --prefix)  echo /usr ;;
    --version) echo "openclaw-apt-brew-shim 1.0" ;;
    install)   exit 0 ;;
    *)         exit 0 ;;
esac
EOF

USER node

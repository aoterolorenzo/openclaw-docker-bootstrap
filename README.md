# OpenClaw Docker Bootstrap

A reproducible, secured Docker setup of [OpenClaw](https://openclaw.ai).
Clone, run one script, get a working agent runtime with all skill
dependencies pre-installed and the runtime state laid out as plain files on
your filesystem so you can poke at everything.

## Prerequisites

- **Docker Desktop** running. (Mac, Windows, or Linux. Free, install from
  <https://docs.docker.com/get-docker/>.)
- **About 5 GB of free disk** for the derived image.
- **`openssl`** (already on macOS/Linux; on Windows use WSL or Git Bash).

That is it. Docker carries Node, Python, ffmpeg, the works — nothing else
to install on the host.

## Quick start

```bash
git clone https://github.com/aoterolorenzo/openclaw-docker-bootstrap.git
cd openclaw-docker-bootstrap
./setup.sh
```

The script will:

1. Check Docker is up.
2. Create `.env` from `.env.example` and generate a unique gateway token.
3. Build a derived image (`openclaw-with-deps:local`) on top of the official
   `alpine/openclaw` image — this is the slow step (~3 min the first time,
   cached afterwards).
4. Run the **onboarding wizard** interactively. You will be asked for an LLM
   provider (OpenAI, Anthropic, etc.) and an API key. The token, model
   choice, skill installs, and other prefs are recorded under `./config/`.
5. Run `openclaw doctor --fix` to download the bundled plugin runtime deps
   (Playwright, MCP SDK, undici, etc.) into a Docker named volume.
6. Start the gateway daemon (`docker compose up -d`).
7. Print a one-click URL with your token embedded so the browser logs in
   automatically.

When it finishes you will see something like:

```
Web UI (token included in fragment, auto-login):
    http://127.0.0.1:18789/#token=<your-token>
```

Open that in your browser. If asked to approve a "device pairing" request,
run from another terminal:

```bash
docker compose run --rm openclaw-cli devices list
docker compose run --rm openclaw-cli devices approve <request-id>
```

## Setup via an AI agent

If you would rather have an agent (Claude Code, Cursor, Claude Desktop with
shell access, etc.) drive the install for you, paste the prompt below into
it. The agent does the non-interactive prep; you run the wizard yourself
in your own terminal so the wizard talks to you directly (and your API
key never passes through the agent's chat).

### What you need first

| Requirement                           | Why                                                                  | How to verify                          |
| ------------------------------------- | -------------------------------------------------------------------- | -------------------------------------- |
| Docker Desktop, running               | Container runtime + image build                                      | `docker info` returns a daemon block   |
| Git                                   | Cloning this repo                                                    | `git --version`                        |
| An AI agent that can run shell        | Claude Code, Cursor (with terminal), Claude Desktop with shell, etc. | —                                      |
| LLM provider API key                  | OpenClaw routes to it                                                | OpenAI / Anthropic recommended         |
| **A budget cap on that key**          | Hard floor against runaway loops. Required for unattended use.       | OpenAI: Project → Limits → Budget      |
| ~5 GB free disk                       | Derived Docker image                                                 | —                                      |

### The prompt

Paste this verbatim into your AI agent and send. Replace nothing.

````markdown
You are setting up OpenClaw locally for me on this machine, using a pre-built Docker bootstrap repo. We work in three phases: you do the non-interactive prep (phase 1), I run the interactive onboarding wizard in my own terminal (phase 2), and you finalize and verify (phase 3). Don't improvise; ask me whenever a step needs input I haven't given.

REPO
https://github.com/aoterolorenzo/openclaw-docker-bootstrap

GROUND RULES
- You cannot drive an interactive wizard. Your shell tool runs one-shot commands and returns their output; it does not keep a stdin/TTY pipe open across turns. The OpenClaw onboarding wizard at the heart of this setup is interactive (clack-style prompts on /dev/tty) and will hang if you try to run it through your tool. Phase 2 is mine — you print the exact command, I run it.
- Never paste, log, or store my API key. I'll enter it directly into the wizard in my own terminal. If anything you read on disk after onboarding contains the key (e.g. `config/agents/main/agent/auth-profiles.json`), redact it before quoting it back to me.
- Don't modify `docker-compose.yml`, `docker-compose.override.yml`, `Dockerfile`, `setup.sh`, or `update.sh` in the repo. The override and Dockerfile carry deliberate fixes against known upstream bugs.
- Don't commit anything to git. The repo's `.gitignore` already excludes `.env`, `config/`, and `openclaw-workspace/`.
- Don't run aggressive repair flags (`--force`, `--generate-gateway-token`) without asking.
- If a step fails, paste the verbatim error and ask before retrying. Do not loop.

PHASE 1 — your turn (non-interactive prep)

1. Confirm Docker is running. Run `docker info >/dev/null 2>&1`; if it errors, stop and tell me to start Docker Desktop, then wait for my confirmation.

2. Clone the repo to `~/openclaw` (ask me first if you'd rather use a different path):
       git clone https://github.com/aoterolorenzo/openclaw-docker-bootstrap.git ~/openclaw

3. From `~/openclaw`, bootstrap `.env` and generate a unique gateway token (idempotent — re-running is safe):
       cd ~/openclaw
       cp -n .env.example .env
       grep -qE '^OPENCLAW_GATEWAY_TOKEN=$' .env && {
           tok=$(openssl rand -hex 32)
           awk -v t="$tok" '/^OPENCLAW_GATEWAY_TOKEN=$/{print "OPENCLAW_GATEWAY_TOKEN=" t; next}{print}' .env > .env.tmp && mv .env.tmp .env
       }

4. Build the derived Docker image. This is the slow step (~3 min the first time, cached afterwards):
       docker compose build openclaw-gateway

5. Print the handoff below VERBATIM and STOP. Don't run anything else until I come back and say I'm done.

       ── PHASE 2 IS YOURS ─────────────────────────────────────────────
       Open a terminal app on your machine:
   
       - macOS:    Press Cmd+Space, type "Terminal", press Enter. (Or
                   use iTerm2 / Warp if you have one.)
       - Linux:    Press Ctrl+Alt+T, or open "Terminal" / "Konsole" /
                   "GNOME Terminal" from your app launcher.
       - Windows:  Open Windows Terminal or PowerShell from the Start
                   menu. If Docker Desktop is configured with the WSL 2
                   backend (recommended), open your WSL distribution
                   (e.g. "Ubuntu") from the Start menu instead — the
                   commands below assume a Unix-style shell.
   
       Then in that terminal, run:
   
           cd ~/openclaw
           docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
               dist/index.js onboard --mode local --no-install-daemon
   
       Wizard guidance:
       - Provider: pick the one you have an API key for.
       - API key: paste it INTO THE WIZARD. Don't paste it into the AI chat.
       - Default / primary model: pick a low-cost tier — OpenClaw will
         keep calling this model continuously while the gateway is up,
         so the tier you pick directly drives your monthly bill. Words
         like "mini", "haiku", "flash", "nano", "lite", "8b" usually
         mean cheap. Avoid "opus", "pro", "flagship", "ultra", or
         anything sold as "most capable".
       - Configure skills now?: Yes.
       - "Install missing skill dependencies" (multi-select): leave ALL
         the defaults checked — `clawhub`, `mcporter`, `nano-pdf`,
         `summarize`, `tmux`, `video-frames`. The Docker image already
         carries everything they need (apt: tmux, ffmpeg, ca-certs; uv
         via Astral; npm globals: mcporter, clawhub, @steipete/summarize;
         plus a brew shim that satisfies the brew-centric upstream
         installer — bugs openclaw#57555, #73955, #69002).
       - "Set <PROVIDER>_API_KEY for <skill>?" prompts (goplaces, notion,
         openai-whisper-api, sag/elevenlabs, etc.): say YES only if you
         actually have a key for that service. Otherwise say NO — you
         can wire any of them up later by editing
         `./config/openclaw.json` or running the corresponding
         `openclaw auth ...` command.
       - Anything else the wizard asks: your call.
   
       When the wizard prints "Onboarding complete" (and you've exited
       any TUI it may have launched at the end with Ctrl+C), come back
       here and tell me "done".
       ────────────────────────────────────────────────────────────────

PHASE 3 — your turn again, after I confirm

6. Repair bundled plugin runtime deps non-interactively (safe migrations only):
       docker compose run --rm openclaw-cli doctor --fix --non-interactive
   It may report nothing, or pull a few deps. Either is fine.

7. Recreate the gateway with the fresh config and wait for /healthz:
       docker compose up -d --force-recreate openclaw-gateway
       for _ in $(seq 1 30); do
           curl -fsS -o /dev/null http://127.0.0.1:18789/healthz && break
           sleep 1
       done

8. Read the token from `.env` and print my auto-login URL on its own line:
       echo "http://127.0.0.1:18789/#token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d= -f2-)"

9. Tell me to open that URL. Then print this exact block VERBATIM so I have a self-contained recipe in case I hit a pairing prompt later (the gateway asks every new browser/device to be approved once before it can talk to it):

       ── If your browser shows "device pairing required (requestId: <id>)" ──
       
       Option A — ask me to do it: paste the requestId in this AI chat
       and I'll run the approval for you.
       
       Option B — do it yourself: open a terminal, then:
       
           cd ~/openclaw
           docker compose run --rm openclaw-cli devices list      # shows pending requests
           docker compose run --rm openclaw-cli devices approve <id>
       
       Refresh the browser tab afterwards.
       ─────────────────────────────────────────────────────────────────────

WHEN DONE
Reply with one short paragraph containing the URL on its own line, the model I picked (ask me if you don't already know — don't infer from disk), and the editable on-disk paths: ./config/openclaw.json, ./openclaw-workspace/skills/, ./openclaw-workspace/agents/.
````

## What lives where

After `setup.sh` finishes, your project directory looks like:

```
openclaw-docker-bootstrap/
├── README.md                    this file
├── setup.sh                     the bootstrap script
├── docker-compose.yml           upstream verbatim — do not edit
├── docker-compose.override.yml  local tweaks
├── Dockerfile                   image with skill deps + brew shim
├── resolv.conf                  custom DNS resolvers (1.1.1.1 / 8.8.8.8)
├── .env.example                 template you copy from
├── .env                         your filled config (gitignored)
├── config/                      gateway state (gitignored)
│   ├── openclaw.json            main config — provider, token, skills
│   ├── agents/                  per-agent settings
│   ├── credentials/             channel credentials
│   ├── logs/                    gateway logs
│   └── ...
└── openclaw-workspace/          agent workspace (gitignored)
    ├── skills/                  installed skills, edit the markdown freely
    ├── agents/                  agent identity, memory, transcripts
    └── ...
```

**Both `config/` and `openclaw-workspace/` are bind-mounted into the
container.** Anything you change on the host is visible to the gateway
immediately. After editing `openclaw.json` or anything that affects startup,
restart the gateway to pick it up:

```bash
docker compose restart openclaw-gateway
```

For workspace-only changes (skill markdown, memory files) the gateway
re-reads on demand — no restart needed.

## Daily commands

| Action                  | Command                                          |
| ----------------------- | ------------------------------------------------ |
| Start                   | `docker compose up -d openclaw-gateway`          |
| Stop                    | `docker compose down`                            |
| Live logs               | `docker compose logs -f openclaw-gateway`        |
| Restart (reload config) | `docker compose restart openclaw-gateway`        |
| Health check            | `curl http://127.0.0.1:18789/healthz`            |
| Open Web UI             | URL from `./setup.sh` output (token in fragment) |
| Open TUI (terminal)     | `docker compose run --rm openclaw-cli tui`       |
| Run any CLI subcommand  | `docker compose run --rm openclaw-cli <cmd>`     |
| List installed skills   | `docker compose run --rm openclaw-cli skills list` |
| List/approve devices    | `docker compose run --rm openclaw-cli devices list` |
| Repair bundled deps     | `docker compose run --rm openclaw-cli doctor --fix` |

## Editing skills and config

The point of mounting `config/` and `openclaw-workspace/` to the host is so
you can edit them with a normal editor:

- **Add/remove a skill manifest:** drop or remove a folder under
  `openclaw-workspace/skills/`. Restart the gateway to register it.
- **Tune the system prompt for an agent:** edit
  `openclaw-workspace/agents/<agent-id>/SOUL.md` (or `IDENTITY.md`,
  `AGENTS.md`, etc.).
- **Switch model or change auth:** edit `config/openclaw.json` or run the
  onboarding again (`docker compose run --rm openclaw-cli onboard ...`).

## Troubleshooting

### "device pairing required (requestId: ...)"

The gateway requires the browser to be paired the first time. Approve it
from a terminal:

```bash
docker compose run --rm openclaw-cli devices approve <request-id>
```

### `LLM request failed: network connection error`

Almost always either: (a) the gateway just started and Docker Desktop's
internal resolver had a transient miss, or (b) your API key is wrong and
the provider returns a generic network error. Wait 30 seconds and retry; if
it persists, check the key with `docker compose logs openclaw-gateway | grep -iE 'auth|provider|key'`.

### `EAI_AGAIN` from npm during onboarding

The override mounts `resolv.conf` with public resolvers
(`1.1.1.1`, `8.8.8.8`) into both services to avoid this. If it still
hits, restart Docker Desktop and re-run `setup.sh` (it is idempotent).

### `brew not installed` on Linux

This is a known upstream limitation: the skills installer hardcodes a
`brew` lookup with no native-package-manager fallback (see openclaw issues
[#57555](https://github.com/openclaw/openclaw/issues/57555),
[#73955](https://github.com/openclaw/openclaw/pull/73955),
[#69002](https://github.com/openclaw/openclaw/pull/69002)). This repo's
Dockerfile installs the actual binaries (`tmux`, `ffmpeg`) via `apt` and
ships a `brew` shim that returns success, so the skills work even though
the upstream installer takes the brew path. The one exception is
`summarize`: we install it as the npm package `@steipete/summarize` instead
of from `steipete/tap` (which is mac-cask only).

### Bundled plugin deps missing

If you see "Bundled plugin runtime deps are missing" in the wizard, run:

```bash
docker compose run --rm openclaw-cli doctor --fix
docker compose restart openclaw-gateway
```

## Security notes

- The gateway authenticates **every** Web UI / WS request with the token
  from `.env`. Each clone of this repo gets a fresh token from `setup.sh`.
- `.env` is gitignored — do **not** commit your filled file.
- The default bind is `lan`, which means the port maps to `0.0.0.0:18789`
  on the host. Only your token holders can do anything; if you need
  loopback-only on Linux, switch `OPENCLAW_GATEWAY_BIND=loopback` in
  `.env`.
- The cli container drops `NET_RAW`/`NET_ADMIN` and runs with
  `no-new-privileges` (from upstream).
- All API keys you enter live in `config/openclaw.json` and
  `config/credentials/`, both gitignored.

## Updating

```bash
./update.sh
```

`update.sh` refreshes everything from upstream in one shot:

1. Re-fetches `docker-compose.yml` from `openclaw/openclaw` main.
2. `docker compose build --pull` to re-pull the `alpine/openclaw` base image
   from Docker Hub and rebuild the derived `openclaw-with-deps:local` image
   on top of it.
3. `docker compose up -d --force-recreate openclaw-gateway` so the running
   container moves to the new image.
4. Waits for `/healthz` and prints the version that is now running.

Your `docker-compose.override.yml`, `Dockerfile`, `.env`, `config/`, and
`openclaw-workspace/` are left untouched. If the upstream upgrade adds new
bundled plugin runtime deps, run `docker compose run --rm openclaw-cli doctor --fix`
afterwards.

## Resetting / starting over

```bash
docker compose down -v          # stop + remove the named volume
rm -rf config openclaw-workspace .env
./setup.sh                      # back to a clean slate
```

`docker compose down -v` also wipes the `openclaw-plugin-runtime-deps`
named volume so the next `doctor --fix` repopulates it cleanly.

## What is in the derived image

| Layer            | What                                                         |
| ---------------- | ------------------------------------------------------------ |
| Base             | `alpine/openclaw` (Debian 12 underneath, despite the name)   |
| `apt-get`        | `tmux`, `ffmpeg`, `curl`, `ca-certificates`                  |
| Astral installer | `uv` and `uvx` in `/usr/local/bin`                           |
| `npm install -g` | `mcporter`, `clawhub`, `@steipete/summarize`                 |
| Brew shim        | `/usr/local/bin/brew` returning `0` for `install`            |

This makes the upstream onboarding wizard succeed end-to-end on Linux
without having to install Homebrew inside the container or fight the
brew-centric skills installer.

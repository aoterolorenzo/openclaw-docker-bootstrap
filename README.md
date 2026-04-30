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

## Updating the upstream compose

The `docker-compose.yml` is identical to the file in the OpenClaw repo on
GitHub. To pull the latest version without losing your local tweaks:

```bash
curl -fsSL https://raw.githubusercontent.com/openclaw/openclaw/main/docker-compose.yml \
    -o docker-compose.yml
```

Your `docker-compose.override.yml` and `Dockerfile` are unaffected.

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

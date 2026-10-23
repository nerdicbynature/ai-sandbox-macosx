# AI Sandbox (Docker Compose, Rancher Desktop on macOS)

An isolated workspace for **Claude Code**, **OpenCode** and **GitHub Copilot CLI**.
The sandbox has no internet access of its own. Every request goes through a
**mitmproxy** that terminates TLS, so you can watch every HTTP(S) request live.

```
 Mac (Rancher Desktop / dockerd)
 ┌────────────────────────────────────────────────────────────────────┐
 │  network "sandbox-net" (internal: no gateway, no internet)         │
 │  ┌──────────────────────┐   HTTP(S)_PROXY    ┌──────────────────┐  │
 │  │ sandbox              │ ─────────────────▶ │ proxy (mitmweb)  │──┼──▶ internet
 │  │ user dev, cap_drop   │      :8080         │ network "egress" │  │
 │  │ read-only rootfs     │                    │ UI :8081 ────────┼──┼──▶ http://localhost:8081
 │  │ /workspace ◀─ ~/dev  │ ◀── CA certificate (public only, ro) ─│  │
 │  └──────────────────────┘                    └──────────────────┘  │
 └────────────────────────────────────────────────────────────────────┘
```

## Contents

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Proxy, sandbox and the sub-sandboxes (profiles `go`, `python`) |
| `sandbox/` | Sandbox image: `node:lts-bookworm-slim` + dev/debug tools + `gh` + the three harnesses |
| `proxy/` | mitmproxy image + addon (CA export, access log, allowlist, TLS passthrough) |
| `scripts/keychain-env.sh` | Loads tokens from the macOS Keychain as env vars into the current bash shell |
| `scripts/keychain-store.sh` | Stores tokens in the Keychain |
| `config/claude`, `config/opencode`, `config/copilot` | Default configs, mounted to `~/.claude`, `~/.config/opencode`, `~/.copilot` |
| `images/go-k8s`, `images/python` | Sub-sandboxes built **on top of** the sandbox image |

**Why a Node base image?** Claude Code, Copilot CLI and the OpenCode installer are all
distributed via npm (Copilot CLI needs Node ≥ 22). `node:lts-bookworm-slim` is Debian, so
`apt` works as usual. Swap the base via the build arg `BASE_IMAGE` (e.g. `node:lts-trixie-slim`).

## Requirements

* Rancher Desktop with container engine **dockerd (moby)** (Preferences → Container Engine).
  With containerd/nerdctl, `additional_contexts` and health checks are not reliable.
* Recommended: VM type **VZ** with mount type **virtiofs** (faster, clean permissions on bind mounts).
* The workspace folder must exist (`mkdir -p ~/dev`) and live under `$HOME`
  (Rancher Desktop shares only the home directory with its VM by default).

## Quick start

```bash
cp .env.example .env                    # optional: adjust WORKSPACE_DIR, limits, ...

# once: store tokens in the Keychain (value is prompted for, hidden)
scripts/keychain-store.sh ANTHROPIC_API_KEY      # or CLAUDE_CODE_OAUTH_TOKEN
scripts/keychain-store.sh COPILOT_GITHUB_TOKEN
scripts/keychain-store.sh GITHUB_TOKEN

# every time
source scripts/keychain-env.sh          # only sets env vars, starts nothing
docker compose up -d --build
docker compose exec sandbox bash
sandbox-doctor                          # inside the sandbox: checks proxy, CA and connectivity
```

Inside the sandbox, `claude`, `opencode`, `copilot`, `gh` and `git` are ready to use.
mitmweb UI: <http://localhost:8081> (password from `MITMWEB_PASSWORD`, otherwise a token from
`docker compose logs proxy`). Compact access log: `docker compose logs -f proxy`.

Switch the workspace: `WORKSPACE_DIR=~/dev/project-x docker compose up -d`.

## Tokens

`scripts/keychain-env.sh` looks up generic passwords in the Keychain with service
`ai-sandbox` and account = variable name, and exports what it finds.
`docker-compose.yml` passes the variables through only if they are set.

| Variable | Used by |
|---|---|
| `ANTHROPIC_API_KEY` | Claude Code (API key) and OpenCode (Anthropic provider) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code with a Pro/Max subscription, created with `claude setup-token` |
| `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `OPENCODE_API_KEY` | OpenCode providers (OpenAI, OpenRouter, OpenCode Zen) |
| `COPILOT_GITHUB_TOKEN` | Copilot CLI (fine-grained PAT with the "Copilot Requests" permission) |
| `GITHUB_TOKEN` / `GH_TOKEN` | `gh` and `git push/pull` over HTTPS (gh is set up as git credential helper) |

More variables: `AI_SANDBOX_TOKEN_VARS="FOO BAR" source scripts/keychain-env.sh`, and add them
under `environment:` in `docker-compose.yml`. Different Keychain service: `AI_SANDBOX_KEYCHAIN_SERVICE=...`.

Note: anything available as an env var inside the container can be read by the AI and sent
out through the proxy. Use narrowly scoped, short-lived tokens.

## Default configs ("stop asking me")

* **Claude Code** (`config/claude/settings.json`): `defaultMode: bypassPermissions` plus an allow list.
  `CLAUDE_CONFIG_DIR` points to `~/.claude`, so `.claude.json` (login, onboarding) also lives in
  the mounted folder. On first start, Claude asks once to confirm bypass mode.
* **OpenCode** (`config/opencode/opencode.json`): `edit`, `bash`, `webfetch` = `allow`, autoupdate off.
* **Copilot CLI** (`config/copilot/config.json`): `/workspace` as trusted folder; in addition,
  `copilot` is an alias for `copilot --allow-all-tools --allow-all-paths` inside the sandbox.

The tools write their runtime data (sessions, logins, history) into the same folders.
`.gitignore` keeps them out of git; only the defaults are versioned.

Harness updates: autoupdate is disabled (the global packages are owned by root). Instead run
`docker compose build --no-cache sandbox`, or pin versions via build args
(`CLAUDE_CODE_VERSION`, `OPENCODE_VERSION`, `COPILOT_VERSION`).

## Security model

Sandbox:
* unprivileged user `dev` (configurable UID/GID), **no sudo**, no Docker socket
* `cap_drop: ALL`, `no-new-privileges`, `privileged: false`, private IPC namespace
* read-only root filesystem; only `/workspace`, `$HOME` (volume) and `/tmp` (tmpfs) are writable
* limits for memory, CPU and PIDs
* attached only to `sandbox-net` (`internal: true`): no default gateway, no published ports.
  Even a program that ignores the proxy settings cannot reach the internet.
* receives only the **public** CA certificate, never the proxy's private key

Proxy:
* also runs without capabilities, read-only, as user `mitmproxy`
* mitmweb UI published on the Mac's `127.0.0.1` only
* optional **allowlist** (`ALLOWED_HOSTS` in `.env`); everything else gets a `403`

Deliberate limits:
* `/workspace` is writable. The AI can change anything there that you can. Use git.
* Without an allowlist the sandbox can reach any domain (but everything is logged).
* `apt install` is **not possible at runtime** (no root). This is intentional. Add packages to
  `sandbox/Dockerfile` or a sub-image and run `docker compose build`.
  Language package managers (`npm`, `pip --user`, `uv`, `go install`) work in home/workspace.
* `ping` does not work (needs `CAP_NET_RAW`). `strace`/`gdb` work for processes you start yourself.

### How the CA gets into the sandbox

The proxy creates its CA on first start (volume `mitm-conf`), and the addon copies only
`mitmproxy-ca-cert.pem` into the volume `mitm-ca-public`. The sandbox starts only once the
proxy is healthy (certificate present). Its entrypoint builds `/tmp/ca/ca-bundle.crt`
(system CAs + mitmproxy CA), which `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`,
`GIT_SSL_CAINFO` and `PIP_CERT` point to. Node/Bun use `NODE_EXTRA_CA_CERTS`.
Node honors `HTTPS_PROXY` through `NODE_USE_ENV_PROXY=1`.

Force a new CA: `docker compose down && docker volume rm ai-sandbox_mitm-conf ai-sandbox_mitm-ca-public`.

Services with client certificates (e.g. a Kubernetes API) or certificate pinning can be
excluded from decryption via `MITM_IGNORE_HOSTS` in `.env` (regex, comma-separated).

## Sub-sandboxes

Both build on the sandbox image via `additional_contexts: sandbox-base: service:sandbox` and
inherit all hardening, proxy and mount settings (YAML anchor `x-sandbox`).

```bash
docker compose --profile go up -d --build
docker compose exec sandbox-go bash

docker compose --profile python up -d --build
docker compose exec sandbox-python bash
```

**Go + Kubernetes** (`images/go-k8s`): Go (latest or `GO_VERSION`), gopls, dlv, staticcheck,
goimports, gofumpt, govulncheck, gotestsum, golangci-lint, kubectl, helm, k9s, kustomize,
kubectx/kubens, stern, kubeconform, yq, setup-envtest.
`kind`/`minikube` are intentionally missing: they would need a Docker socket.
Clusters are reached through the proxy; put a kubeconfig e.g. into `/workspace`.
For Rancher Desktop's own Kubernetes cluster, add its API host to `MITM_IGNORE_HOSTS`.

**Python** (`images/python`): uv/uvx, Python 3.13 (uv-managed, `PYTHON_VERSION`), ruff, mypy,
pyright, pytest, ipython, pre-commit, poetry, nox, tox, pipx, build headers for native packages.

### iOS / Xcode

There is no Linux container image with the Xcode build tools: `xcodebuild`, the iOS SDK,
the simulator, `codesign` and `notarytool` exist only on macOS, and Rancher Desktop runs
Linux containers. Xcode itself can of course run on the Mac and work on the same folder.

To let the AI build, test and release from inside the sandbox anyway, the build has to run
on macOS and be *triggered* from the sandbox. Keep in mind that `xcodebuild` executes run
script phases and SwiftPM plugins from the project, so building AI-modified code directly
on your Mac means the AI can run code on the host. Two clean options:

1. **macOS VM with [Tart](https://tart.run) as build agent**: the VM shares the workspace
   folder, holds Xcode, signing certificates and the App Store Connect key, and exposes a
   small build API with a fixed set of commands (build, test, archive, fastlane lanes) that
   the sandbox reaches through the proxy. Fast and local, and the Mac stays isolated.
2. **GitHub Actions on macOS runners**: the AI pushes a branch or tag with `gh`, CI builds,
   tests and releases. Simplest and safest, but slower and it uses macOS minutes.

A good combination is Tart for the fast build/test loop and CI for releases.

## Troubleshooting

* **`ERR_PROXY_TUNNEL` / "Unable to connect to Anthropic services"**: the proxy rejected the
  CONNECT request, usually because the proxy itself cannot reach the internet. Run
  `sandbox-doctor` in the sandbox and look for `[ERROR]` lines in `docker compose logs proxy`.
  Check the proxy's own connectivity with
  `docker compose exec proxy python -c "import urllib.request as u; print(u.urlopen('https://platform.claude.com').status)"`.
* **Permission denied on `/workspace` or `config/*`**: set `SANDBOX_UID`/`SANDBOX_GID` in `.env`
  to your Mac's `id -u`/`id -g` (usually `501`/`20`) and rebuild. With virtiofs this is
  usually not needed.
* **TLS errors inside the sandbox**: check `echo $SSL_CERT_FILE; ls -l /tmp/ca/` and
  `docker compose logs proxy`. Restart the sandbox after deleting the CA volumes.
* **A tool ignores the proxy**: it will not get out at all (internal network). Configure
  `http://proxy:8080` explicitly in that tool.
* **403 "Blocked by ai-sandbox proxy"**: the host is missing from `ALLOWED_HOSTS`.
* **Finding the mitmweb token**: `docker compose logs proxy | grep -i token`.

# cuda-env

CUDA development container based on `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04`.

This repo provides two images:

- `panjd123/cuda-env`: the main CUDA/C++/Python development environment
- `panjd123/docker-lite`: a smaller Docker-focused debug environment

Common behavior:

- both images default to `zsh`
- both images run `sshd` in the foreground by default
- both images install dotfile in non-interactive mode
- both images install `codex` and `claude`
- `claude` is installed with the official `curl -fsSL https://claude.ai/install.sh | bash` flow
- both images support optional import of `.dev-secrets/claude/`, `.dev-secrets/codex/`, `.dev-secrets/github/gh_token`, `.dev-secrets/huggingface/token`, and `.dev-secrets/ssh/`

## Installation

If you are bringing this repo up on a new machine, start with
[docs/installation.md](docs/installation.md).

That document is intentionally narrow: it tells an AI agent or human operator
how to choose the right image, build it, start it, and verify the installation.

## Quick Start

Build the main image:

```bash
./compose.sh build
```

Show wrapper help:

```bash
./compose.sh --help
```

Start the main container:

```bash
./compose.sh up -d
```

Enter it:

```bash
docker exec -it cuda-env-dev /usr/bin/zsh
```

The repo is mounted at `/workspace/cuda-env`. `/workspace` itself is a separate
persistent workspace root, backed by `CUDA_ENV_WORKSPACE_DIR` and defaulting to
`.cuda-env-state/workspace` under the repo.

SSH into it:

```bash
ssh -p 22847 "${LOCAL_USER:-$(id -un)}"@127.0.0.1
```

Stop it:

```bash
./compose.sh down
```

## Wrapper Script

`compose.sh` is the default entrypoint for the main environment. It wraps
`docker compose` and automatically:

- exports `LOCAL_USER` / `LOCAL_UID` / `LOCAL_GID` from the current host user
- falls back to `uid=0,gid=0` for the container user when rootless Docker cannot map the host uid/gid into image builds
- auto-detects `NVIDIA_DRIVER_BRANCH` from the host when available
- auto-enables target-specific Docker socket overrides from the active Docker endpoint when possible
- always builds with host networking
- auto-enables target-specific proxy environment overrides when `CUDA_ENV_USE_PROXY=1`
- prepares optional encrypted dev secrets during build-like commands
- supports both the main CUDA environment and the smaller `docker-lite` target

Useful commands:

```bash
./compose.sh build
./compose.sh up -d
./compose.sh down
./compose.sh ps
./compose.sh logs -f
./compose.sh doctor
./compose.sh config
./compose.sh exec cuda-dev /usr/bin/zsh
./compose.sh compose-help
```

## Proxy

If this machine needs the host proxy setup, use one switch:

```bash
CUDA_ENV_USE_PROXY=1 ./compose.sh build
```

When enabled, the wrapper will:

- prefer host lowercase `http_proxy` / `https_proxy` / `no_proxy`
- fall back to uppercase values or Docker daemon proxy settings
- forward proxy variables into build args and runtime environment
- keep runtime on bridge networking

Regardless of the proxy switch:

- build uses host networking
- runtime stays on bridge networking
- containers should still be able to reach other LAN machines by IP
- `host.docker.internal` is always mapped to the host gateway

## Secrets

The repo supports a local plaintext secrets directory and a repo-safe encrypted
bundle:

- plaintext: `.dev-secrets/`
- encrypted: `.dev-secrets.encrypted/bundle.tar.gz.enc`

Seal local secrets:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-seal
```

Restore local plaintext secrets:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-unseal
```

Build with encrypted secrets only:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh build
```

Supported import targets inside images:

- `.dev-secrets/claude/` -> `~/.claude/`
- `.dev-secrets/codex/` -> `~/.codex/`
- `.dev-secrets/github/gh_token` -> `gh auth login --with-token`
- `.dev-secrets/huggingface/token` -> `~/.cache/huggingface/token`
- `.dev-secrets/ssh/` -> `~/.ssh/`

More details: [docs/secrets.md](docs/secrets.md)

## Docker Socket

The main image and `docker-lite` both use Docker-outside-of-Docker through the
active Docker Unix socket, not a nested daemon.

When the current Docker endpoint resolves to a Unix socket and
`CUDA_ENV_USE_DOCKER_SOCKET` is not `0`, `compose.sh` automatically enables the
socket override for the selected target. That works for both standard
`/var/run/docker.sock` setups and rootless endpoints such as
`/run/user/<uid>/docker.sock`.

If you want to disable that behavior:

```bash
CUDA_ENV_USE_DOCKER_SOCKET=0 ./compose.sh up -d
```

Inspect what `compose.sh` resolved on the current machine:

```bash
./compose.sh doctor
```

## Validation

What matters on the host side is already preserved under rootless Docker:

- host `ps` shows the container shim and GPU workloads as the host user running the rootless Docker daemon
- host `nvidia-smi` reports CUDA processes launched from `cuda-env` with the same host-side owner
- the main image includes `ncu`, and profiling from inside `cuda-env` works when the host driver allows performance counters

Useful checks:

```bash
./compose.sh doctor
docker exec cuda-env-dev /usr/bin/zsh -lc 'ncu --version'
```

The doctor output also shows `host_workspace_dir`, which is the host directory
mounted at `/workspace`.

## Docker Lite

`docker-lite` is a separate smaller image for debugging Docker builds, socket
access, proxy handling, and Codex-driven iteration outside the full CUDA stack.

Files:

- `Dockerfile.docker-lite`
- `docker-compose.docker-lite.yml`

Build and start it through the same wrapper:

```bash
./compose.sh lite build
./compose.sh lite up -d
```

For cross-host portability, prefer `compose.sh`. If you need to run
`docker compose` directly, first resolve the active Docker Unix socket and pick
the matching override file:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
export DEV_SECRETS_ARCHIVE_B64="$(
  openssl enc -d -aes-256-cbc -pbkdf2 -pass env:DEV_SECRETS_PASSPHRASE \
    -in .dev-secrets.encrypted/bundle.tar.gz.enc | base64 -w0
)"
export DOCKER_SOCKET_PATH="$(
  docker context inspect "$(docker context show)" \
    --format '{{ (index .Endpoints "docker").Host }}' |
    sed -n 's#^unix://##p'
)"
if [[ "${DOCKER_SOCKET_PATH}" == /run/user/*/docker.sock ]]; then
  export SOCKET_OVERRIDE_FILE=docker-compose.docker-lite.rootless-socket.yml
else
  export DOCKER_SOCKET_GID="$(stat -c '%g' "${DOCKER_SOCKET_PATH}")"
  export SOCKET_OVERRIDE_FILE=docker-compose.docker-lite.socket.yml
fi
docker compose \
  -f docker-compose.docker-lite.yml \
  -f "${SOCKET_OVERRIDE_FILE}" \
  up -d --build
```

Enter it:

```bash
./compose.sh lite exec docker-lite /usr/bin/zsh
```

or:

```bash
docker exec -it docker-lite-dev /usr/bin/zsh
```

SSH into it:

```bash
ssh -p 22848 "${LOCAL_USER:-$(id -un)}"@127.0.0.1
```

## Docs

- [CUDA_ALTERNATIVES.md](CUDA_ALTERNATIVES.md): switching `/usr/local/cuda` between installed toolkits
- [docs/secrets.md](docs/secrets.md): encrypted secrets workflow and import behavior
- [docs/runtime-notes.md](docs/runtime-notes.md): GPU, SSH, Docker socket, and migration notes
- [AGENTS.md](AGENTS.md): short cross-agent instructions and command map
- [CLAUDE.md](CLAUDE.md): Claude-compatible entrypoint that imports `AGENTS.md`
- [docs/installation.md](docs/installation.md): installation guide for new machines and AI agents

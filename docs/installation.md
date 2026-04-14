# Installation

This document is the installation entrypoint for a new machine.

Its purpose is narrow: after reading this file, an AI agent or human operator
should be able to choose the right target, build it, start it, and verify that
the environment is usable.

For secret details, read `docs/secrets.md`.
For runtime debugging, read `docs/runtime-notes.md`.

If the repo is not present locally yet, clone:

```bash
git clone https://github.com/panjd123/cuda-env.git
cd cuda-env
```

Build always uses host networking. `CUDA_ENV_USE_PROXY=1` only controls whether
host proxy variables are injected into build and runtime.

Image tags use a repo-owned version plus an optional CUDA suffix:

- `cuda-env`: `${CUDA_ENV_IMAGE_VERSION}-cuda${CUDA_VERSION}`
- `docker-lite`: `${CUDA_ENV_IMAGE_VERSION}`
- `cuda-env-template`: `${CUDA_ENV_IMAGE_VERSION}-cuda${CUDA_VERSION}`
- `docker-lite-template`: `${CUDA_ENV_IMAGE_VERSION}`

Build modes:

- `CUDA_ENV_BUILD_MODE=full`: build the template and final stages locally
- `CUDA_ENV_BUILD_MODE=template`: pull the published template image first, then build only the final local stage

This behavior assumes a modern Docker build path with BuildKit enabled. If the
host Docker version is too old, or the build does not actually use BuildKit,
the `template` mode may fail to skip the unused local template stage as
intended, which can make the build slower than expected.

## 0. AI Interaction Rules

If you are an AI agent following this document, use these rules:

- If the user has not specified whether they want `docker-lite` or `cuda-env`, ask before building anything.
- If the host does not appear to support NVIDIA and the user did not explicitly ask for `cuda-env`, recommend `docker-lite`.
- If build-time secret import may be needed and only `.dev-secrets.encrypted/bundle.tar.gz.enc` is available, ask the user for `DEV_SECRETS_PASSPHRASE` before building.
- If neither plaintext secrets nor encrypted secrets are present, continue without secrets and do not ask for a passphrase.
- If base-image pull speed is very slow, especially below `1 MB/s` for a sustained period, stop and report that to the user before continuing.
- Do not use `README.md` as the installation manual; this file is the source of truth.

## 1. Choose a Target

Start with `docker-lite` unless CUDA is explicitly required.

- `docker-lite`: safest default, works for Docker debugging, shell setup,
  Codex, Claude, SSH, GitHub auth, Hugging Face token, and proxy validation
- `cuda-env`: use only when the host has NVIDIA support and the task needs CUDA

If the host does not have usable NVIDIA support, do not start with `cuda-env`.

## 2. Host Prerequisites

Before building, verify:

- the repo is cloned locally
- `docker` works on the host
- `docker compose` works on the host
- Docker is new enough to use modern BuildKit-based builds
- if Docker socket passthrough is expected, `/var/run/docker.sock` exists
- if proxy is needed, host `http_proxy` / `https_proxy` / `no_proxy` are set
- if only encrypted secrets are available, `DEV_SECRETS_PASSPHRASE` is known

Useful checks:

```bash
docker info
docker buildx version
docker compose version
ls -l /var/run/docker.sock
printf 'http_proxy=%s\nhttps_proxy=%s\nno_proxy=%s\n' "${http_proxy:-}" "${https_proxy:-}" "${no_proxy:-}"
```

If `docker buildx version` is missing or the Docker installation is very old,
expect `CUDA_ENV_BUILD_MODE=template` to be slower than expected because the
unused local template stage may not be skipped cleanly.

If you plan to use `cuda-env`, also verify:

```bash
command -v nvidia-smi && nvidia-smi
```

Optional version override:

```bash
export CUDA_ENV_IMAGE_VERSION=v2
```

Optional build mode override:

```bash
export CUDA_ENV_BUILD_MODE=template
```

## 3. Pre-pull the Base Image First

Before starting a full build, pull the base image explicitly and watch the
download speed.

For `docker-lite`:

```bash
docker pull ubuntu:24.04
```

For `cuda-env`:

```bash
docker pull nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04
```

If the observed pull speed is very slow, especially below `1 MB/s` for a
sustained period, do not blindly continue into `./compose.sh build`.

Instead:

- stop and report the slow pull speed to the user
- explain that the build is likely to be slow or unstable for the same reason
- discuss mitigation first, such as proxy configuration, Docker registry mirror,
  LAN proxy reachability, or another network path

Only continue with the full build after that check is acceptable.

## 4. Secrets Behavior

Build-time secrets resolve in this order:

1. `.dev-secrets/`
2. `.dev-secrets.encrypted/bundle.tar.gz.enc`
3. no secret import

Decision rules:

- If `.dev-secrets/` exists locally, use it directly and do not ask for a passphrase.
- If `.dev-secrets/` does not exist but `.dev-secrets.encrypted/bundle.tar.gz.enc` exists, ask the user for `DEV_SECRETS_PASSPHRASE` unless they already provided it.
- If neither exists, continue without secrets.

If only the encrypted bundle exists locally:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
```

Possible imported targets include:

- `~/.claude/`
- `~/.codex/`
- `~/.ssh/`
- GitHub CLI authenticated state
- `~/.cache/huggingface/token`

For `cuda-env`, the runtime only bind-mounts Hugging Face cache subdirectories
from the host. The token file itself stays inside the built image/user home, so
an old host cache token should not override the imported token anymore.

## 5. Install `docker-lite`

Use this on a fresh machine unless you know you need CUDA immediately.

Without proxy:

```bash
./compose.sh lite build
./compose.sh lite up -d
./compose.sh lite exec docker-lite /usr/bin/zsh
```

With proxy:

```bash
CUDA_ENV_USE_PROXY=1 ./compose.sh lite build
./compose.sh lite up -d
./compose.sh lite exec docker-lite /usr/bin/zsh
```

With a pulled published template:

```bash
CUDA_ENV_BUILD_MODE=template ./compose.sh lite build
CUDA_ENV_BUILD_MODE=template ./compose.sh lite up -d
CUDA_ENV_BUILD_MODE=template ./compose.sh lite exec docker-lite /usr/bin/zsh
```

## 6. Install `cuda-env`

Only do this on a host with usable NVIDIA support.

Without proxy:

```bash
./compose.sh build
./compose.sh up -d
./compose.sh exec cuda-dev /usr/bin/zsh
```

With proxy:

```bash
CUDA_ENV_USE_PROXY=1 ./compose.sh build
./compose.sh up -d
./compose.sh exec cuda-dev /usr/bin/zsh
```

With a pulled published template:

```bash
CUDA_ENV_BUILD_MODE=template ./compose.sh build
CUDA_ENV_BUILD_MODE=template ./compose.sh up -d
CUDA_ENV_BUILD_MODE=template ./compose.sh exec cuda-dev /usr/bin/zsh
```

## 7. Verify the Installation

For `docker-lite`:

```bash
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'codex --version'
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'claude --version'
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'gh auth status'
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'test -f ~/.cache/huggingface/token && echo hf-token-ok'
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'docker version'
./compose.sh lite exec docker-lite /usr/bin/zsh -lc 'ps -o pid,comm,args -p 1'
```

For `cuda-env`, add:

```bash
./compose.sh exec cuda-dev /usr/bin/zsh -lc 'nvidia-smi'
./compose.sh exec cuda-dev /usr/bin/zsh -lc 'nvcc --version'
```

## 8. Common Failure Modes

Check these first:

- the build needed proxy but `CUDA_ENV_USE_PROXY=1` was not set
- the base image pull was already too slow, but the build was started anyway
- only encrypted secrets were present, but `DEV_SECRETS_PASSPHRASE` was not set
- the host Docker socket is missing or inaccessible
- `cuda-env` was chosen on a host without usable NVIDIA support
- on very large hosts, Rust source builds may need capped parallelism; retry with `CARGO_BUILD_JOBS=32 ./compose.sh build`

Useful commands:

```bash
./compose.sh ps
./compose.sh logs -f
./compose.sh config
```

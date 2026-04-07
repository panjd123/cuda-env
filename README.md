# cuda-env

CUDA development container based on `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04`.

This repo provides two images:

- `panjd123/cuda-env`: the main CUDA/C++/Python development environment
- `panjd123/docker-lite`: a smaller Docker-focused debug environment

Common behavior:

- both images default to `zsh`
- both images run `sshd` in the foreground by default
- both images install dotfile in non-interactive mode
- both images support optional import of `.dev-secrets/codex/` and `.dev-secrets/ssh/`

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

SSH into it:

```bash
ssh -p 22847 cc@127.0.0.1
```

Stop it:

```bash
./compose.sh down
```

## Wrapper Script

`compose.sh` is the default entrypoint for the main environment. It wraps
`docker compose` and automatically:

- exports `LOCAL_USER` / `LOCAL_UID` / `LOCAL_GID` from the current host user
- auto-detects `NVIDIA_DRIVER_BRANCH` from the host when available
- auto-enables target-specific Docker socket overrides when a host Docker socket is present
- auto-enables target-specific proxy overrides when `CUDA_ENV_USE_PROXY=1`
- prepares optional encrypted dev secrets during build-like commands
- supports both the main CUDA environment and the smaller `docker-lite` target

Useful commands:

```bash
./compose.sh build
./compose.sh up -d
./compose.sh down
./compose.sh ps
./compose.sh logs -f
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
- switch build to host networking
- forward proxy variables into build args and runtime environment
- keep runtime on bridge networking and add host reachability helpers

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

- `.dev-secrets/codex/` -> `~/.codex/`
- `.dev-secrets/ssh/` -> `~/.ssh/`

More details: [docs/secrets.md](/home/panjunda/cuda-env/docs/secrets.md)

## Docker Socket

The main image and `docker-lite` both use Docker-outside-of-Docker through the
host socket, not a nested daemon.

When `/var/run/docker.sock` exists and `CUDA_ENV_USE_DOCKER_SOCKET` is not `0`,
`compose.sh` automatically enables the socket override for the main container.

If you want to disable that behavior:

```bash
CUDA_ENV_USE_DOCKER_SOCKET=0 ./compose.sh up -d
```

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

If you want to run it directly with `docker compose`, for example when preparing
an encrypted secrets archive yourself:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
export DEV_SECRETS_ARCHIVE_B64="$(
  openssl enc -d -aes-256-cbc -pbkdf2 -pass env:DEV_SECRETS_PASSPHRASE \
    -in .dev-secrets.encrypted/bundle.tar.gz.enc | base64 -w0
)"
export DOCKER_SOCKET_GID="$(stat -c '%g' /var/run/docker.sock)"
docker compose \
  -f docker-compose.docker-lite.yml \
  -f docker-compose.docker-lite.socket.yml \
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
ssh -p 22848 cc@127.0.0.1
```

## Docs

- [CUDA_ALTERNATIVES.md](/home/panjunda/cuda-env/CUDA_ALTERNATIVES.md): switching `/usr/local/cuda` between installed toolkits
- [docs/secrets.md](/home/panjunda/cuda-env/docs/secrets.md): encrypted secrets workflow and import behavior
- [docs/runtime-notes.md](/home/panjunda/cuda-env/docs/runtime-notes.md): GPU, SSH, Docker socket, and migration notes

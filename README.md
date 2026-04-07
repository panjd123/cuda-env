# cuda-env

CUDA development container based on `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04`.

## Quick Start

Build the image:

```bash
./compose.sh build
```

If this machine needs the host proxy setup, use one unified switch:

```bash
CUDA_ENV_USE_PROXY=1 ./compose.sh build
```

When `CUDA_ENV_USE_PROXY=1` is enabled, `compose.sh` will:

- switch the build phase to host networking
- prefer the host's lowercase `http_proxy` / `https_proxy` / `no_proxy`, then fall back to uppercase values or Docker daemon proxy settings
- forward the resolved proxy values into image build args
- forward the same proxy variables into the running container
- bake the same proxy exports into the container user's `~/.bashrc`
- enable the proxy-specific Compose override so the container still runs on bridge networking and can reach LAN resources and the host via `host.docker.internal`

If you also want host secrets imported into the image without committing plaintext files to GitHub:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-seal
CUDA_ENV_USE_PROXY=1 ./compose.sh build
```

The intended workflow is:

- keep local plaintext files under `.dev-secrets/`, which is ignored by git
- generate a repo-safe encrypted bundle at `.dev-secrets.encrypted/bundle.tar.gz.enc`
- keep both `.dev-secrets/` and `.dev-secrets.encrypted/` out of the Docker build context
- during `build`, use plaintext `.dev-secrets/` if it exists locally; otherwise decrypt `.dev-secrets.encrypted/bundle.tar.gz.enc` on the host and send the plaintext archive into the image build
- restore supported subdirectories into the container user's home only if they exist in the bundle

Useful commands:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-seal
./compose.sh secrets-unseal
```

### Secrets Layout

The plaintext directory is a single bundle root:

```text
.dev-secrets/
  codex/
    auth.json
    config.toml
  ssh/
    id_ed25519
    id_ed25519.pub
    config
    known_hosts
```

Current supported targets are:

- `.dev-secrets/codex/` -> container `~/.codex/`
- `.dev-secrets/ssh/` -> container `~/.ssh/`

### Secrets Notes

- `.dev-secrets/` is local plaintext and should not be pushed.
- `.dev-secrets.encrypted/bundle.tar.gz.enc` is the repo-safe encrypted bundle you can commit and push.
- `.dockerignore` excludes both `.dev-secrets/` and `.dev-secrets.encrypted/`, so neither plaintext nor encrypted secrets are sent as Docker build context.
- Decryption happens on the host inside `compose.sh`, not inside Docker build and not inside the final image.
- Because decryption happens on the host, the image does not need `DEV_SECRETS_PASSPHRASE`, and the passphrase is not baked into image layers.
- During `./compose.sh build`, the script resolves secrets in this order:
  - if local plaintext `.dev-secrets/` exists, use it directly
  - otherwise, if `.dev-secrets.encrypted/bundle.tar.gz.enc` exists, decrypt it on the host and use that result
  - otherwise, build continues without importing any secrets
- `DEV_SECRETS_PASSPHRASE` is required for:
  - `./compose.sh secrets-seal`
  - `./compose.sh secrets-unseal`
  - `./compose.sh build` when only the encrypted bundle exists and local plaintext `.dev-secrets/` does not exist
- If you edit files under `.dev-secrets/`, run `./compose.sh secrets-seal` again before pushing, otherwise the encrypted bundle in git will be stale.
- If you clone the repo onto another machine and only have `.dev-secrets.encrypted/bundle.tar.gz.enc`, either:
  - run `./compose.sh secrets-unseal` first to restore local plaintext `.dev-secrets/`
  - or run `DEV_SECRETS_PASSPHRASE=... ./compose.sh build` and let the script decrypt on the host during build
- The Docker build import is optional. If `DEV_SECRETS_ARCHIVE_B64` is empty, the image skips all secret copy steps.
- Inside the image, each supported target is copied only when its source directory exists. For example, if the bundle has only `codex/` and no `ssh/`, then `~/.ssh/` is left untouched.
- Imported files end up in the container user's home, and the build sets directory permissions to `0700` and file permissions to `0600`.

The resulting image tag is:

```text
panjd123/cuda-env:13.2.0
```

Start the container:

```bash
./compose.sh up -d
```

Enter the container:

```bash
docker exec -it cuda-env-dev /usr/bin/zsh
```

SSH into the container from the host:

```bash
ssh -p 22847 cc@127.0.0.1
```

Stop and remove the container:

```bash
./compose.sh down
```

## Current Behavior

- `compose.sh` prefers `~/.local/bin/docker` when it exists.
- On this machine, that `docker` is a Podman-compatible wrapper pointed at the NVMe-backed container store.
- `CUDA_ENV_USE_PROXY=1` is the single switch for proxy-aware behavior:
  - build uses host networking
  - build and runtime both receive the host proxy environment
  - runtime keeps bridge networking and also gets `host.docker.internal`
- Secret handling is split:
  - plaintext local files live in `.dev-secrets/` and are git-ignored
  - repo-safe encrypted secrets live in `.dev-secrets.encrypted/bundle.tar.gz.enc`
  - build imports optional secrets into the image only after they are resolved on the host
- `compose.sh` now auto-detects `NVIDIA_DRIVER_BRANCH` from the host driver version when you do not set it yourself.
- when `CUDA_ENV_USE_PROXY` is not set, the base Compose behavior is unchanged
- The container is configured with `restart: unless-stopped`.
- The container now stays alive by running `sshd` in the foreground.
- Host port `22847` is mapped to container port `22`.
- The default interactive shell inside the container is now `zsh`, with `oh-my-zsh` preinstalled for the development user.
- The container's default user remains the current host user (`cc` on this machine). `sshd` itself is started through `sudo`, so SSH can still bind to port `22` without changing the container's default user to root.

## GPU Notes

- The image includes CUDA 13.2 as base and also installs CUDA 12.8 and 13.0 side by side.
- `/usr/local/cuda` currently defaults to CUDA 12.8 via `update-alternatives`.
- The image also installs host-matched NVIDIA userspace packages:

```text
libnvidia-compute-${NVIDIA_DRIVER_BRANCH}
nvidia-compute-utils-${NVIDIA_DRIVER_BRANCH}
nvidia-utils-${NVIDIA_DRIVER_BRANCH}
```

- This is required so the container has `nvidia-smi`, `libcuda.so`, and `libnvidia-ml.so`.
- `compose.sh` will auto-export `NVIDIA_DRIVER_BRANCH` from the host driver version, and an explicitly set `NVIDIA_DRIVER_BRANCH` still wins.
- If host auto-detection is unavailable and you bypass `compose.sh`, `docker-compose.yml` still falls back to `560`.

## SSH Notes

- `docker-compose.yml` maps:

```text
22847 -> container:22
```

- The container manages its own `~/.ssh` directory. This repo does not mount the host's `~/.ssh`.
- The image creates the directory:

```text
/home/${LOCAL_USER}/.ssh/authorized_keys
```

- But the actual `authorized_keys` content must be provisioned inside the container by your own bootstrap flow.
- On this machine, the expectation is that your dotfiles/bootstrap tooling will install the public key into the container user automatically.
- If that provisioning step does not happen, `sshd` will still listen on port `22847`, but public-key login will fail until `authorized_keys` exists inside the container.

## Why `nvidia-smi` Was Missing

`nvidia-smi` is not part of the CUDA toolkit. It comes from the NVIDIA driver userspace packages.

Without those packages, a container can still see `/dev/nvidia*`, but:

- `nvidia-smi` is missing
- CUDA runtime may fail to talk to the host driver cleanly

Installing the matching userspace packages fixed that.

## Environment Pitfalls

### 1. `docker` Here Is Not Docker Engine

On this host, `docker` is Podman CLI emulation. If behavior looks unusual, check:

```bash
type docker
docker info
```

`compose.sh` now prefers `~/.local/bin/docker` so it uses the intended wrapper even if your shell `PATH` is different.

### 2. Storage Location Matters

This setup expects your own container storage to live on the larger NVMe-backed path rather than the default tmpfs-backed location.

If image pulls or builds unexpectedly consume the old store, check:

```bash
docker info --format '{{.Store.GraphRoot}}'
```

The expected graph root on this machine is:

```text
/mnt/nvme0n1/cc-containers/storage
```

### 3. Driver Branch Must Match the Host

If you move this setup to another machine, the container's `NVIDIA_DRIVER_BRANCH` must match the host driver major branch.

Check the host:

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1
```

Examples:

- `560.35.05` -> use `NVIDIA_DRIVER_BRANCH=560`
- `570.x` -> use `NVIDIA_DRIVER_BRANCH=570`
- `590.48.01` -> use `NVIDIA_DRIVER_BRANCH=590`

`compose.sh` now does this detection automatically from the host `nvidia-smi` output. If this is wrong, `nvidia-smi` inside the container may fail or CUDA runtime may report driver/runtime incompatibility.

### 4. `nvidia-smi` and CUDA Device Count Can Differ

`nvidia-smi` reports physical GPUs. CUDA runtime may report fewer devices if one GPU is in a different mode, for example MIG enabled on only part of the machine.

That happened on this host:

- `nvidia-smi -L` showed 4 H100 GPUs
- a CUDA runtime probe enumerated 3 CUDA devices

Do not assume that mismatch always means the container is broken.

### 5. Rootless / Podman Compose Quirks

Two specific issues showed up here:

- `sleep infinity` was less predictable than an explicit shell loop under `podman-compose`
- a more complex shell command using `trap : TERM INT; ...` was mis-rendered by `podman-compose` and caused restart loops
- keeping the default container user as the host-mapped user while still running `sshd` was simplest via `sudo /usr/sbin/sshd -D -e`

The current long-running command is:

```bash
sudo /usr/sbin/sshd -D -e
```

## Useful Checks

Verify `nvidia-smi` inside the container:

```bash
docker exec cuda-env-dev nvidia-smi -L
```

Verify CUDA toolkit selection:

```bash
docker exec cuda-env-dev /bin/bash -lc 'update-alternatives --display cuda'
```

Verify container status:

```bash
./compose.sh ps
```

Verify SSH is listening on the host:

```bash
ssh-keyscan -p 22847 127.0.0.1
```

Verify the image exists:

```bash
docker images | rg 'panjd123/cuda-env'
```

## If You Switch Machines Later

The first things to re-check are:

1. `type docker`
2. `docker info --format '{{.Store.GraphRoot}}'`
3. `nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1`
4. `docker exec cuda-env-dev nvidia-smi -L`
5. `docker exec cuda-env-dev /bin/bash -lc 'nvcc --version'`

If any of those differ from expectations, fix them before debugging application code.

# cuda-env

CUDA development container based on `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04`.

## Quick Start

Build the image:

```bash
./compose.sh build
```

Start the container:

```bash
./compose.sh up -d
```

Enter the container:

```bash
docker exec -it cuda-env-dev /bin/bash
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
- The container is configured with `restart: unless-stopped`.
- The container now stays alive by running `sshd` in the foreground.
- Host port `22847` is mapped to container port `22`.
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
- `NVIDIA_DRIVER_BRANCH` is passed from `docker-compose.yml` and currently defaults to `560`.

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

If this is wrong, `nvidia-smi` inside the container may fail or CUDA runtime may report driver/runtime incompatibility.

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
docker images | rg cuda-dev
```

## If You Switch Machines Later

The first things to re-check are:

1. `type docker`
2. `docker info --format '{{.Store.GraphRoot}}'`
3. `nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1`
4. `docker exec cuda-env-dev nvidia-smi -L`
5. `docker exec cuda-env-dev /bin/bash -lc 'nvcc --version'`

If any of those differ from expectations, fix them before debugging application code.

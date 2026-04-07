# Runtime Notes

These notes are intentionally separated from the main README. They are useful
for debugging, migration, and host-specific setup validation.

## Current Behavior

- `compose.sh` prefers `~/.local/bin/docker` when it exists.
- On this machine, `docker` is the standard Docker Engine CLI talking to `/var/run/docker.sock`.
- `CUDA_ENV_USE_PROXY=1` is the single switch for proxy-aware behavior:
  - build uses host networking
  - build and runtime both receive the host proxy environment
  - runtime keeps bridge networking and also gets `host.docker.internal`
- When `/var/run/docker.sock` exists and `CUDA_ENV_USE_DOCKER_SOCKET` is not set to `0`, `compose.sh` automatically adds the target-specific socket override so either image can talk to the host Docker engine.
- `compose.sh` auto-detects `NVIDIA_DRIVER_BRANCH` from the host driver version unless you set it explicitly.
- Both images default to running `sshd` in the foreground from their Dockerfiles.
- Host port `22847` maps to `cuda-env:22`.
- Host port `22848` maps to `docker-lite:22`.
- The default interactive shell is `zsh`, with `oh-my-zsh`, `zsh-autosuggestions`, and `zsh-syntax-highlighting`.

## GPU Notes

- The main image uses CUDA 13.2 as the base and also installs CUDA 12.8 and 13.0 side by side.
- `/usr/local/cuda` currently defaults to CUDA 12.8 through `update-alternatives`.
- The image also installs host-matched NVIDIA userspace packages:

```text
libnvidia-compute-${NVIDIA_DRIVER_BRANCH}
nvidia-compute-utils-${NVIDIA_DRIVER_BRANCH}
nvidia-utils-${NVIDIA_DRIVER_BRANCH}
```

- This is required so the container has `nvidia-smi`, `libcuda.so`, and `libnvidia-ml.so`.
- If `NVIDIA_DRIVER_BRANCH` is empty, the Dockerfile skips these userspace packages entirely.

## SSH Notes

- The repo does not mount the host `~/.ssh` directly.
- Images create the container user's `~/.ssh` directory and can optionally import it from `.dev-secrets/ssh/`.
- Dotfile installation can also write `authorized_keys`.
- If `authorized_keys` is missing inside the container, `sshd` will still listen, but public-key login will fail.

## Why `nvidia-smi` Was Missing

`nvidia-smi` is not part of the CUDA toolkit. It comes from the NVIDIA driver
userspace packages.

Without those packages, a container can still see `/dev/nvidia*`, but:

- `nvidia-smi` is missing
- CUDA runtime may fail to talk to the host driver cleanly

Installing the matching userspace packages fixes that.

## Environment Pitfalls

### 1. Docker Engine Expectations

On this host, `docker` talks directly to Docker Engine through the default Unix
socket:

```bash
type docker
docker info
```

Expected endpoint:

```text
unix:///var/run/docker.sock
```

### 2. Storage Location

If pulls or builds consume the wrong disk, check:

```bash
docker info --format '{{.DockerRootDir}}'
```

Expected root on this machine:

```text
/var/lib/docker
```

### 3. Docker Socket Access Inside Containers

The intended model is Docker-outside-of-Docker via the host socket, not a
nested daemon.

What must be true:

- Docker CLI exists inside the container
- the host socket is mounted, usually `/var/run/docker.sock`
- the container user receives the socket gid through `group_add`

Useful host checks:

```bash
ls -l /var/run/docker.sock
getent group docker
stat -c '%g' /var/run/docker.sock
```

### 4. Driver Branch Must Match the Host

If the host has NVIDIA driver support and you want the userspace packages inside
the image, `NVIDIA_DRIVER_BRANCH` must match the host driver major branch.

Check the host:

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1
```

Examples:

- `560.35.05` -> `NVIDIA_DRIVER_BRANCH=560`
- `570.x` -> `NVIDIA_DRIVER_BRANCH=570`
- `590.48.01` -> `NVIDIA_DRIVER_BRANCH=590`

### 5. `nvidia-smi` and CUDA Device Count Can Differ

`nvidia-smi` reports physical GPUs. CUDA runtime may report fewer devices if a
GPU is in a different mode, for example partial MIG usage.

Do not assume that mismatch always means the container is broken.

### 6. Long-Running Process Choice

Both images intentionally keep a simple long-running foreground process:

```text
sudo /usr/sbin/sshd -D -e
```

That keeps the default user mapped to the host identity while still letting the
container expose SSH on port `22`.

## Useful Checks

Verify `nvidia-smi` inside the main container:

```bash
docker exec cuda-env-dev nvidia-smi -L
```

Verify CUDA toolkit selection:

```bash
docker exec cuda-env-dev /usr/bin/zsh -lc 'update-alternatives --display cuda'
```

Verify container status:

```bash
./compose.sh ps
```

Verify SSH is listening:

```bash
ssh-keyscan -p 22847 127.0.0.1
```

Verify the image exists:

```bash
docker images | rg 'panjd123/cuda-env'
```

## If You Switch Machines Later

The first checks to rerun are:

1. `type docker`
2. `docker info --format '{{.DockerRootDir}}'`
3. `nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1`
4. `docker exec cuda-env-dev nvidia-smi -L`
5. `docker exec cuda-env-dev /usr/bin/zsh -lc 'nvcc --version'`

If those differ from expectations, fix them before debugging application code.

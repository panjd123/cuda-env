# cuda-env

Docker-based personal development environment with two targets: `cuda-env` for
full CUDA work and `docker-lite` for lighter Docker-oriented debugging.

## Installation

Installation details live in [docs/installation.md](docs/installation.md).

### For Human

Paste this to your AI agent:

```text
Clone `https://github.com/panjd123/cuda-env.git` if needed, then read
`docs/installation.md` and follow it as the only installation guide.
```

## Images

This repo maintains two main images:

- `cuda-env`: a fuller CUDA/C++/Python image for NVIDIA hosts
- `docker-lite`: a smaller image for Docker-oriented debugging and remote development

It also maintains reusable template images so you can either rebuild
everything locally or pull a template first and only rebuild the final local
user layer.

## Shared Behavior

Both images are designed to provide a consistent interactive environment:

- default shell is `zsh`
- `sshd` starts by default
- `bash` and `zsh` share the same environment setup
- `codex` and `claude` are preinstalled
- dotfile is installed non-interactively
- host Docker socket passthrough is supported
- build uses host networking

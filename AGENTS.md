# Agent Guide

This file is for repo-maintenance guidance, not installation steps.

## Scope

- Keep new-machine installation instructions in `docs/installation.md`.
- Keep secret behavior in `docs/secrets.md`.
- Keep runtime and host-specific notes in `docs/runtime-notes.md`.

## Repo Map

- `Dockerfile`: main CUDA image
- `Dockerfile.docker-lite`: smaller Docker-oriented image
- `compose.sh`: wrapper around `docker compose`
- `README.md`: human-facing overview
- `docs/installation.md`: installation guide for new machines

## Maintenance Rule

If setup, proxy, secret, shell, or runtime behavior changes, update the
matching file in `docs/` and keep `README.md` aligned.

#!/usr/bin/env bash

set -euo pipefail

export LOCAL_USER="${LOCAL_USER:-$(id -un)}"
export LOCAL_UID="${LOCAL_UID:-$(id -u)}"
export LOCAL_GID="${LOCAL_GID:-$(id -g)}"

exec docker compose "$@"

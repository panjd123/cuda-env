#!/usr/bin/env bash

set -euo pipefail

if [[ -x "${HOME}/.local/bin/docker" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
  DOCKER_BIN="${HOME}/.local/bin/docker"
else
  DOCKER_BIN="docker"
fi

export LOCAL_USER="${LOCAL_USER:-$(id -un)}"
export LOCAL_UID="${LOCAL_UID:-$(id -u)}"
export LOCAL_GID="${LOCAL_GID:-$(id -g)}"
export BUILDAH_FORMAT="${BUILDAH_FORMAT:-docker}"

DEV_SECRETS_DIR=".dev-secrets"
DEV_SECRETS_ENCRYPTED_DIR=".dev-secrets.encrypted"
DEV_SECRETS_ENCRYPTED_FILE="${DEV_SECRETS_ENCRYPTED_DIR}/bundle.tar.gz.enc"
COMPOSE_BASE_FILE="docker-compose.yml"
SOCKET_OVERRIDE_FILE="docker-compose.socket.yml"
PROXY_OVERRIDE_FILE="docker-compose.proxy.yml"

print_help() {
  printf '%s\n' \
    'Usage:' \
    '  ./compose.sh [cuda|lite] <docker-compose-subcommand> [args...]' \
    '  ./compose.sh help' \
    '  ./compose.sh --help' \
    '' \
    'This script wraps `docker compose` for this repository and automatically:' \
    '  - exports LOCAL_USER / LOCAL_UID / LOCAL_GID from the current host user' \
    '  - auto-detects NVIDIA_DRIVER_BRANCH from the host when available' \
    '  - enables target-specific Docker socket overrides when a host Docker socket is present' \
    '  - enables target-specific proxy overrides when CUDA_ENV_USE_PROXY=1' \
    '  - prepares optional encrypted dev secrets during build-like commands' \
    '' \
    'Wrapper-only commands:' \
    '  secrets-seal       Encrypt .dev-secrets/ into .dev-secrets.encrypted/bundle.tar.gz.enc' \
    '  secrets-unseal     Decrypt .dev-secrets.encrypted/bundle.tar.gz.enc back into .dev-secrets/' \
    '  compose-help       Show upstream `docker compose` top-level help' \
    '' \
    'Common examples:' \
    '  ./compose.sh build' \
    '  ./compose.sh lite build' \
    '  ./compose.sh up -d' \
    '  ./compose.sh lite up -d' \
    '  ./compose.sh down' \
    '  ./compose.sh ps' \
    '  ./compose.sh logs -f' \
    '  ./compose.sh exec cuda-dev /usr/bin/zsh' \
    '  ./compose.sh lite exec docker-lite /usr/bin/zsh' \
    '  ./compose.sh config' \
    '  ./compose.sh build --no-cache' \
    '' \
    'Targets:' \
    '  cuda        Main CUDA environment (default when omitted)' \
    '  lite        Smaller Docker-focused debug environment' \
    '' \
    'Compose passthrough:' \
    '  Any command other than the wrapper-only commands above is forwarded to `docker compose`.' \
    '  Example: `./compose.sh build --help` shows help for `docker compose build`.' \
    '' \
    'Environment switches:' \
    '  CUDA_ENV_USE_PROXY=1          Enable proxy-aware build/runtime overrides' \
    '  CUDA_ENV_USE_DOCKER_SOCKET=0  Disable automatic Docker socket override' \
    '  NVIDIA_DRIVER_BRANCH=590      Override host driver branch auto-detection' \
    '  DEV_SECRETS_PASSPHRASE=...    Required for secrets-seal / secrets-unseal, and encrypted build import' \
    '  DOCKER_SOCKET_PATH=...        Override the Docker socket path to mount' \
    '  DOCKER_SOCKET_GID=...         Override the Docker socket group id inside compose' \
    '' \
    'Notes:' \
    '  - `./compose.sh --help` shows this wrapper help.' \
    '  - `./compose.sh lite --help` also shows this wrapper help.' \
    '  - `./compose.sh compose-help` shows top-level `docker compose` help.' \
    '  - `./compose.sh <subcommand> --help` shows help for that Docker Compose subcommand.'
}

parse_target() {
  case "${1:-}" in
    cuda|cuda-env|main)
      shift
      ;;
    lite|docker-lite)
      COMPOSE_BASE_FILE="docker-compose.docker-lite.yml"
      SOCKET_OVERRIDE_FILE="docker-compose.docker-lite.socket.yml"
      PROXY_OVERRIDE_FILE="docker-compose.docker-lite.proxy.yml"
      shift
      ;;
  esac

  ARGS=("$@")
}

handle_help_command() {
  case "${1:-}" in
    ""|-h|--help|help)
      print_help
      exit 0
      ;;
    compose-help)
      exec "${DOCKER_BIN}" compose --help
      ;;
  esac
}

detect_docker_socket() {
  local socket_path="${DOCKER_SOCKET_PATH:-/var/run/docker.sock}"

  if [[ "${CUDA_ENV_USE_DOCKER_SOCKET:-1}" != "1" ]]; then
    return
  fi

  if [[ ! -S "${socket_path}" ]]; then
    return
  fi

  export DOCKER_SOCKET_PATH="${socket_path}"
  if [[ -z "${DOCKER_SOCKET_GID:-}" ]]; then
    export DOCKER_SOCKET_GID
    DOCKER_SOCKET_GID="$(stat -c '%g' "${socket_path}")"
  fi
}

get_docker_info_proxy() {
  local field="$1"
  local value=""

  value="$("${DOCKER_BIN}" info --format "{{ .${field} }}" 2>/dev/null || true)"
  if [[ -n "${value}" && "${value}" != "<no value>" ]]; then
    printf '%s' "${value}"
  fi
}

sync_proxy_env() {
  local upper_name="$1"
  local lower_name="$2"
  local docker_field="$3"
  local value=""

  if [[ -n "${!lower_name:-}" ]]; then
    value="${!lower_name}"
  elif [[ -n "${!upper_name:-}" ]]; then
    value="${!upper_name}"
  elif [[ "${CUDA_ENV_USE_PROXY:-0}" == "1" ]]; then
    value="$(get_docker_info_proxy "${docker_field}")"
  fi

  if [[ -n "${value}" ]]; then
    export "${upper_name}=${value}"
    export "${lower_name}=${value}"
  fi
}

require_dev_secrets_passphrase() {
  if [[ -z "${DEV_SECRETS_PASSPHRASE:-}" ]]; then
    echo "DEV_SECRETS_PASSPHRASE is required for this secrets operation." >&2
    exit 1
  fi
}

require_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required for this secrets operation." >&2
    exit 1
  fi
}

seal_dev_secrets() {
  require_dev_secrets_passphrase
  require_openssl

  if [[ ! -d "${DEV_SECRETS_DIR}" ]]; then
    echo "Missing ${DEV_SECRETS_DIR}; nothing to seal." >&2
    exit 1
  fi

  mkdir -p "${DEV_SECRETS_ENCRYPTED_DIR}"
  tar -C . -czf - "${DEV_SECRETS_DIR}" | \
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:DEV_SECRETS_PASSPHRASE \
      -out "${DEV_SECRETS_ENCRYPTED_FILE}"
  chmod 0600 "${DEV_SECRETS_ENCRYPTED_FILE}"
  echo "Wrote encrypted secrets bundle to ${DEV_SECRETS_ENCRYPTED_FILE}"
}

unseal_dev_secrets() {
  require_dev_secrets_passphrase
  require_openssl

  if [[ ! -f "${DEV_SECRETS_ENCRYPTED_FILE}" ]]; then
    echo "Missing ${DEV_SECRETS_ENCRYPTED_FILE}; nothing to unseal." >&2
    exit 1
  fi

  openssl enc -d -aes-256-cbc -pbkdf2 -pass env:DEV_SECRETS_PASSPHRASE \
    -in "${DEV_SECRETS_ENCRYPTED_FILE}" | \
    tar -xzf - -C .
  find "${DEV_SECRETS_DIR}" -type d -exec chmod 0700 {} +
  find "${DEV_SECRETS_DIR}" -type f -exec chmod 0600 {} +
  echo "Restored plaintext secrets into ${DEV_SECRETS_DIR}"
}

prepare_dev_secrets_archive() {
  unset DEV_SECRETS_ARCHIVE_B64 || true

  if [[ -d "${DEV_SECRETS_DIR}" ]]; then
    export DEV_SECRETS_ARCHIVE_B64="$(
      tar -C . -czf - "${DEV_SECRETS_DIR}" | base64 -w0
    )"
    return
  fi

  if [[ ! -f "${DEV_SECRETS_ENCRYPTED_FILE}" ]]; then
    return
  fi

  require_dev_secrets_passphrase
  require_openssl

  export DEV_SECRETS_ARCHIVE_B64="$(
    openssl enc -d -aes-256-cbc -pbkdf2 -pass env:DEV_SECRETS_PASSPHRASE \
      -in "${DEV_SECRETS_ENCRYPTED_FILE}" | \
      base64 -w0
  )"
}

should_prepare_dev_secrets_archive() {
  local arg

  for arg in "$@"; do
    case "${arg}" in
      build|up|run|create|--build)
        return 0
        ;;
    esac
  done

  return 1
}

handle_dev_secrets_command() {
  case "${1:-}" in
    secrets-seal)
      seal_dev_secrets
      exit 0
      ;;
    secrets-unseal)
      unseal_dev_secrets
      exit 0
      ;;
  esac
}

detect_nvidia_driver_branch() {
  local driver_version=""
  local driver_branch=""

  if [[ -n "${NVIDIA_DRIVER_BRANCH:-}" ]]; then
    return
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d '[:space:]')"
  fi

  if [[ -z "${driver_version}" && -r /proc/driver/nvidia/version ]]; then
    driver_version="$(sed -n 's/.*Kernel Module[[:space:]]\([0-9][0-9]*\(\.[0-9][0-9]*\)\+\).*/\1/p' /proc/driver/nvidia/version | head -n1)"
  fi

  driver_branch="${driver_version%%.*}"
  if [[ "${driver_branch}" =~ ^[0-9]+$ ]]; then
    export NVIDIA_DRIVER_BRANCH="${driver_branch}"
  fi
}

parse_target "$@"

handle_help_command "${ARGS[0]:-}"
handle_dev_secrets_command "${ARGS[0]:-}"
detect_nvidia_driver_branch
detect_docker_socket
if should_prepare_dev_secrets_archive "${ARGS[@]}"; then
  prepare_dev_secrets_archive
fi

compose_files=("${COMPOSE_FILE:-${COMPOSE_BASE_FILE}}")

if [[ -n "${DOCKER_SOCKET_PATH:-}" ]]; then
  compose_files+=("${SOCKET_OVERRIDE_FILE}")
fi

if [[ "${CUDA_ENV_USE_PROXY:-0}" == "1" ]]; then
  sync_proxy_env "HTTP_PROXY" "http_proxy" "HttpProxy"
  sync_proxy_env "HTTPS_PROXY" "https_proxy" "HttpsProxy"
  sync_proxy_env "NO_PROXY" "no_proxy" "NoProxy"

  if [[ -z "${HTTP_PROXY:-}" && -z "${HTTPS_PROXY:-}" ]]; then
    echo "CUDA_ENV_USE_PROXY=1 is set, but no host proxy environment was found; only the proxy override profile will be enabled." >&2
  fi

  compose_files+=("${PROXY_OVERRIDE_FILE}")
fi

export COMPOSE_FILE="$(IFS=:; printf '%s' "${compose_files[*]}")"

exec "${DOCKER_BIN}" compose "${ARGS[@]}"

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

handle_dev_secrets_command "${1:-}"
detect_nvidia_driver_branch
if should_prepare_dev_secrets_archive "$@"; then
  prepare_dev_secrets_archive
fi

compose_files=("${COMPOSE_FILE:-docker-compose.yml}")

if [[ "${CUDA_ENV_USE_PROXY:-0}" == "1" ]]; then
  sync_proxy_env "HTTP_PROXY" "http_proxy" "HttpProxy"
  sync_proxy_env "HTTPS_PROXY" "https_proxy" "HttpsProxy"
  sync_proxy_env "NO_PROXY" "no_proxy" "NoProxy"

  if [[ -z "${HTTP_PROXY:-}" && -z "${HTTPS_PROXY:-}" ]]; then
    echo "CUDA_ENV_USE_PROXY=1 is set, but no host proxy environment was found; only the proxy override profile will be enabled." >&2
  fi

  compose_files+=("docker-compose.proxy.yml")
fi

export COMPOSE_FILE="$(IFS=:; printf '%s' "${compose_files[*]}")"

exec "${DOCKER_BIN}" compose "$@"

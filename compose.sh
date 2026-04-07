#!/usr/bin/env bash

set -euo pipefail

if [[ -x "${HOME}/.local/bin/docker" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
  DOCKER_BIN="${HOME}/.local/bin/docker"
else
  DOCKER_BIN="docker"
fi

LOCAL_USER_WAS_SET=0
LOCAL_UID_WAS_SET=0
LOCAL_GID_WAS_SET=0
[[ -n "${LOCAL_USER+x}" ]] && LOCAL_USER_WAS_SET=1
[[ -n "${LOCAL_UID+x}" ]] && LOCAL_UID_WAS_SET=1
[[ -n "${LOCAL_GID+x}" ]] && LOCAL_GID_WAS_SET=1

export LOCAL_USER="${LOCAL_USER:-$(id -un)}"
export LOCAL_UID="${LOCAL_UID:-$(id -u)}"
export LOCAL_GID="${LOCAL_GID:-$(id -g)}"
export BUILDAH_FORMAT="${BUILDAH_FORMAT:-docker}"

DEV_SECRETS_DIR=".dev-secrets"
DEV_SECRETS_ENCRYPTED_DIR=".dev-secrets.encrypted"
DEV_SECRETS_ENCRYPTED_FILE="${DEV_SECRETS_ENCRYPTED_DIR}/bundle.tar.gz.enc"
COMPOSE_BASE_FILE="docker-compose.yml"
SOCKET_OVERRIDE_FILE="docker-compose.socket.yml"
ROOTLESS_SOCKET_OVERRIDE_FILE="docker-compose.rootless-socket.yml"
PROXY_OVERRIDE_FILE="docker-compose.proxy.yml"

ensure_directory() {
  local path="$1"

  mkdir -p "${path}" 2>/dev/null
}

resolve_hf_cache_dir() {
  local explicit_dir="${CUDA_ENV_HF_CACHE_DIR:-}"
  local cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
  local preferred_dir="${cache_root%/}/huggingface"
  local fallback_dir="${PWD}/.cuda-env-state/huggingface"

  if [[ -n "${explicit_dir}" ]]; then
    if ! ensure_directory "${explicit_dir}"; then
      echo "compose.sh: CUDA_ENV_HF_CACHE_DIR=${explicit_dir} is not usable; failed to create the directory." >&2
      exit 1
    fi
    printf '%s' "${explicit_dir}"
    return
  fi

  if ensure_directory "${preferred_dir}"; then
    printf '%s' "${preferred_dir}"
    return
  fi

  echo "compose.sh: host cache path ${preferred_dir} is not usable; falling back to ${fallback_dir}." >&2
  if ! ensure_directory "${fallback_dir}"; then
    echo "compose.sh: failed to create fallback cache directory ${fallback_dir}." >&2
    exit 1
  fi
  printf '%s' "${fallback_dir}"
}

resolve_workspace_dir() {
  local explicit_dir="${CUDA_ENV_WORKSPACE_DIR:-}"
  local default_dir="${PWD}/.cuda-env-state/workspace"

  if [[ -n "${explicit_dir}" ]]; then
    if ! ensure_directory "${explicit_dir}"; then
      echo "compose.sh: CUDA_ENV_WORKSPACE_DIR=${explicit_dir} is not usable; failed to create the directory." >&2
      exit 1
    fi
    printf '%s' "${explicit_dir}"
    return
  fi

  if ! ensure_directory "${default_dir}"; then
    echo "compose.sh: failed to create workspace directory ${default_dir}." >&2
    exit 1
  fi
  printf '%s' "${default_dir}"
}

print_help() {
  printf '%s\n' \
    'Usage:' \
    '  ./compose.sh [cuda|lite] <docker-compose-subcommand> [args...]' \
    '  ./compose.sh help' \
    '  ./compose.sh --help' \
    '' \
    'This script wraps `docker compose` for this repository and automatically:' \
    '  - exports LOCAL_USER / LOCAL_UID / LOCAL_GID from the current host user' \
    '  - falls back to uid/gid 0 when rootless Docker cannot map the host uid/gid into builds' \
    '  - auto-detects NVIDIA_DRIVER_BRANCH from the host when available' \
    '  - enables target-specific Docker socket overrides from the active Docker endpoint when possible' \
    '  - enables target-specific proxy overrides when CUDA_ENV_USE_PROXY=1' \
    '  - prepares optional encrypted dev secrets during build-like commands' \
    '' \
    'Wrapper-only commands:' \
    '  secrets-seal       Encrypt .dev-secrets/ into .dev-secrets.encrypted/bundle.tar.gz.enc' \
    '  secrets-unseal     Decrypt .dev-secrets.encrypted/bundle.tar.gz.enc back into .dev-secrets/' \
    '  doctor             Print detected Docker/runtime settings and resolved container identity' \
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
    '  CUDA_ENV_ROOTLESS_UID_FALLBACK=0  Disable automatic uid/gid fallback for rootless Docker' \
    '  NVIDIA_DRIVER_BRANCH=590      Override host driver branch auto-detection' \
    '  DEV_SECRETS_PASSPHRASE=...    Required for secrets-seal / secrets-unseal, and encrypted build import' \
    '  DOCKER_SOCKET_PATH=...        Override the Docker socket path to mount' \
    '  DOCKER_SOCKET_GID=...         Override the Docker socket group id inside compose' \
    '  CUDA_ENV_WORKSPACE_DIR=...    Override the host directory mounted at /workspace' \
    '  CUDA_ENV_HF_CACHE_DIR=...     Override the host Hugging Face cache directory mount' \
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
      ROOTLESS_SOCKET_OVERRIDE_FILE="docker-compose.docker-lite.rootless-socket.yml"
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

docker_context_host() {
  local host=""
  local context_name=""

  if [[ -n "${DOCKER_HOST:-}" ]]; then
    printf '%s' "${DOCKER_HOST}"
    return
  fi

  context_name="$("${DOCKER_BIN}" context show 2>/dev/null || true)"
  if [[ -z "${context_name}" ]]; then
    return
  fi

  host="$("${DOCKER_BIN}" context inspect "${context_name}" --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null | head -n1 || true)"
  if [[ -n "${host}" ]]; then
    printf '%s' "${host}"
  fi
}

resolve_docker_socket_path() {
  local docker_host=""

  if [[ -n "${DOCKER_SOCKET_PATH:-}" ]]; then
    printf '%s' "${DOCKER_SOCKET_PATH}"
    return
  fi

  docker_host="$(docker_context_host)"
  if [[ "${docker_host}" == unix://* ]]; then
    printf '%s' "${docker_host#unix://}"
    return
  fi

  printf '%s' '/var/run/docker.sock'
}

docker_security_options() {
  "${DOCKER_BIN}" info --format '{{range .SecurityOptions}}{{println .}}{{end}}' 2>/dev/null || true
}

docker_is_rootless() {
  local security_options=""

  security_options="$(docker_security_options)"
  grep -Eq '(^|[[:space:]])(name=)?rootless($|[[:space:]])' <<< "${security_options}"
}

lookup_subid_length() {
  local path="$1"
  local user_name="$2"

  if [[ ! -r "${path}" ]]; then
    printf '%s' 0
    return
  fi

  awk -F: -v user_name="${user_name}" '
    $1 == user_name && $3 > max { max = $3 }
    END { print max + 0 }
  ' "${path}" 2>/dev/null
}

detect_docker_socket() {
  local socket_path=""

  if [[ "${CUDA_ENV_USE_DOCKER_SOCKET:-1}" != "1" ]]; then
    return
  fi

  socket_path="$(resolve_docker_socket_path)"
  if [[ ! -S "${socket_path}" ]]; then
    return
  fi

  export DOCKER_SOCKET_PATH="${socket_path}"
  if [[ -z "${DOCKER_SOCKET_GID:-}" ]]; then
    export DOCKER_SOCKET_GID
    DOCKER_SOCKET_GID="$(stat -c '%g' "${socket_path}")"
  fi
}

maybe_enable_rootless_identity_fallback() {
  local subuid_length=0
  local subgid_length=0

  if [[ "${CUDA_ENV_ROOTLESS_UID_FALLBACK:-1}" != "1" ]]; then
    return
  fi

  if (( LOCAL_UID_WAS_SET != 0 || LOCAL_GID_WAS_SET != 0 )); then
    return
  fi

  if ! docker_is_rootless; then
    return
  fi

  subuid_length="$(lookup_subid_length /etc/subuid "$(id -un)")"
  subgid_length="$(lookup_subid_length /etc/subgid "$(id -un)")"

  if (( LOCAL_UID <= subuid_length && LOCAL_GID <= subgid_length )); then
    return
  fi

  echo "compose.sh: active Docker context is rootless and host uid/gid ${LOCAL_UID}:${LOCAL_GID} exceed the mapped subuid/subgid range ${subuid_length}:${subgid_length}; falling back to container uid/gid 0 for user ${LOCAL_USER}." >&2
  export CUDA_ENV_ROOTLESS_FALLBACK_ACTIVE=1
  export CUDA_ENV_ORIGINAL_LOCAL_UID="${LOCAL_UID}"
  export CUDA_ENV_ORIGINAL_LOCAL_GID="${LOCAL_GID}"
  export LOCAL_UID=0
  export LOCAL_GID=0
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

print_doctor() {
  local docker_context=""
  local docker_host=""
  local socket_path=""
  local security_options=""
  local subuid_length=0
  local subgid_length=0
  local fallback_active="${CUDA_ENV_ROOTLESS_FALLBACK_ACTIVE:-0}"
  local docker_rootless="no"
  local hf_cache_dir=""
  local workspace_dir=""

  docker_context="$("${DOCKER_BIN}" context show 2>/dev/null || true)"
  docker_host="$(docker_context_host)"
  socket_path="$(resolve_docker_socket_path)"
  security_options="$(docker_security_options)"
  subuid_length="$(lookup_subid_length /etc/subuid "$(id -un)")"
  subgid_length="$(lookup_subid_length /etc/subgid "$(id -un)")"
  hf_cache_dir="$(resolve_hf_cache_dir)"
  workspace_dir="$(resolve_workspace_dir)"
  if docker_is_rootless; then
    docker_rootless="yes"
  fi

  printf '%s\n' \
    "docker_bin=${DOCKER_BIN}" \
    "docker_context=${docker_context:-unknown}" \
    "docker_host=${docker_host:-unknown}" \
    "docker_socket_path=${socket_path:-unknown}" \
    "docker_socket_present=$([[ -S "${socket_path}" ]] && printf yes || printf no)" \
    "docker_socket_gid=${DOCKER_SOCKET_GID:-unknown}" \
    "docker_rootless=${docker_rootless}" \
    "host_user=$(id -un)" \
    "host_uid=$(id -u)" \
    "host_gid=$(id -g)" \
    "subuid_length=${subuid_length}" \
    "subgid_length=${subgid_length}" \
    "container_user=${LOCAL_USER}" \
    "container_uid=${LOCAL_UID}" \
    "container_gid=${LOCAL_GID}" \
    "rootless_uid_fallback_active=$([[ "${fallback_active}" == "1" ]] && printf yes || printf no)" \
    "host_workspace_dir=${workspace_dir}" \
    "host_hf_cache_dir=${hf_cache_dir}" \
    "nvidia_driver_branch=${NVIDIA_DRIVER_BRANCH:-unknown}"
}

parse_target "$@"

handle_help_command "${ARGS[0]:-}"
handle_dev_secrets_command "${ARGS[0]:-}"
detect_nvidia_driver_branch
detect_docker_socket
maybe_enable_rootless_identity_fallback
export CUDA_ENV_HF_CACHE_DIR="$(resolve_hf_cache_dir)"
export CUDA_ENV_WORKSPACE_DIR="$(resolve_workspace_dir)"
if [[ "${ARGS[0]:-}" == "doctor" ]]; then
  print_doctor
  exit 0
fi
if should_prepare_dev_secrets_archive "${ARGS[@]}"; then
  prepare_dev_secrets_archive
fi

compose_files=("${COMPOSE_FILE:-${COMPOSE_BASE_FILE}}")

if [[ -n "${DOCKER_SOCKET_PATH:-}" ]]; then
  socket_override_file="${SOCKET_OVERRIDE_FILE}"
  if docker_is_rootless; then
    socket_override_file="${ROOTLESS_SOCKET_OVERRIDE_FILE}"
  fi
  compose_files+=("${socket_override_file}")
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

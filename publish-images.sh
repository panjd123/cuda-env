#!/usr/bin/env bash

set -euo pipefail

if [[ -x "${HOME}/.local/bin/docker" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
  DOCKER_BIN="${HOME}/.local/bin/docker"
else
  DOCKER_BIN="docker"
fi

CUDA_ENV_IMAGE_VERSION="${CUDA_ENV_IMAGE_VERSION:-v1}"
CUDA_VERSION="${CUDA_VERSION:-13.2.0}"
NODE_VERSION="${NODE_VERSION:-24.14.1}"
NVM_VERSION="${NVM_VERSION:-v0.40.4}"
CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-32}"
PUBLISH_TARGET="${1:-all}"

sync_proxy_pair() {
  local upper_name="$1"
  local lower_name="$2"
  local value=""

  if [[ -n "${!lower_name:-}" ]]; then
    value="${!lower_name}"
  elif [[ -n "${!upper_name:-}" ]]; then
    value="${!upper_name}"
  fi

  if [[ -n "${value}" ]]; then
    export "${upper_name}=${value}"
    export "${lower_name}=${value}"
  fi
}

add_proxy_build_args() {
  local -n ref="$1"
  local proxy_name=""

  sync_proxy_pair "HTTP_PROXY" "http_proxy"
  sync_proxy_pair "HTTPS_PROXY" "https_proxy"
  sync_proxy_pair "NO_PROXY" "no_proxy"

  for proxy_name in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    if [[ -n "${!proxy_name:-}" ]]; then
      ref+=(--build-arg "${proxy_name}=${!proxy_name}")
    fi
  done
}

cuda_template_ref() {
  printf 'panjd123/cuda-env-template:%s-cuda%s' "${CUDA_ENV_IMAGE_VERSION}" "${CUDA_VERSION}"
}

docker_lite_template_ref() {
  printf 'panjd123/docker-lite-template:%s' "${CUDA_ENV_IMAGE_VERSION}"
}

build_and_push_cuda_template() {
  local image_ref=""
  local build_args=()

  image_ref="$(cuda_template_ref)"
  build_args=(
    --build-arg "CUDA_VERSION=${CUDA_VERSION}"
    --build-arg "NODE_VERSION=${NODE_VERSION}"
    --build-arg "NVM_VERSION=${NVM_VERSION}"
    --build-arg "CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS}"
    --build-arg "NVIDIA_DRIVER_BRANCH="
  )
  add_proxy_build_args build_args

  echo "Building ${image_ref}"
  "${DOCKER_BIN}" build \
    -f Dockerfile \
    --target cuda-env-template \
    --network host \
    "${build_args[@]}" \
    -t "${image_ref}" \
    .

  echo "Pushing ${image_ref}"
  "${DOCKER_BIN}" push "${image_ref}"
}

build_and_push_docker_lite_template() {
  local image_ref=""
  local build_args=()

  image_ref="$(docker_lite_template_ref)"
  build_args=(
    --build-arg "NODE_VERSION=${NODE_VERSION}"
  )
  add_proxy_build_args build_args

  echo "Building ${image_ref}"
  "${DOCKER_BIN}" build \
    -f Dockerfile.docker-lite \
    --target docker-lite-template \
    --network host \
    "${build_args[@]}" \
    -t "${image_ref}" \
    .

  echo "Pushing ${image_ref}"
  "${DOCKER_BIN}" push "${image_ref}"
}

case "${PUBLISH_TARGET}" in
  all)
    build_and_push_cuda_template
    build_and_push_docker_lite_template
    ;;
  cuda)
    build_and_push_cuda_template
    ;;
  lite)
    build_and_push_docker_lite_template
    ;;
  *)
    echo "Usage: ./publish-images.sh [all|cuda|lite]" >&2
    exit 1
    ;;
esac

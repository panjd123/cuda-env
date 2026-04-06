ARG CUDA_VERSION=13.2.0
FROM nvidia/cuda:${CUDA_VERSION}-cudnn-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG LOCAL_USER=devuser
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
ARG GIT_USER=panjd123
ARG GIT_EMAIL=xm_jarden@qq.com
ARG DOTFILE_REPO_URL=https://github.com/panjd123/dotfile.git
ARG NVM_VERSION=v0.40.4
ARG NODE_VERSION=24.14.1
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_CONFIG_ARCHIVE_B64
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CUDA_HOME=/usr/local/cuda

RUN printf '%s\n' \
    'Acquire::Retries "5";' \
    'Acquire::http::Timeout "30";' \
    'Acquire::https::Timeout "30";' \
    > /etc/apt/apt.conf.d/80-cuda-env-retries

# Base system packages for CUDA/C++ development and general shell use.
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    ca-certificates \
    curl \
    wget \
    git \
    git-lfs \
    openssh-server \
    openssh-client \
    rsync \
    gnupg \
    jq \
    unzip \
    zip \
    xz-utils \
    file \
    less \
    neovim \
    vim \
    nano \
    tmux \
    screen \
    htop \
    tree \
    net-tools \
    lsof \
    ripgrep \
    fd-find \
    cloc \
    bash-completion \
    software-properties-common \
    tzdata \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    cmake \
    ninja-build \
    ccache \
    gdb \
    lldb \
    clang \
    clangd \
    lld \
    autoconf \
    automake \
    libtool \
    locales \
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 \
    libopenblas-dev \
    liblapack-dev \
    libboost-all-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    liblzma-dev \
    tk-dev

# Install additional side-by-side CUDA toolkits on top of the 13.2 base image.
RUN if ! apt-cache show cuda-toolkit-12-8 >/dev/null 2>&1; then \
        wget -qO /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
        dpkg -i /tmp/cuda-keyring.deb && \
        rm -f /tmp/cuda-keyring.deb && \
        apt-get update; \
    fi && \
    apt-get install -y --no-install-recommends \
    cuda-toolkit-12-8 \
    cuda-toolkit-13-0 && \
    update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-12.8 120800 && \
    update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-13.0 130000 && \
    update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-13.2 130200 && \
    update-alternatives --set cuda /usr/local/cuda-12.8

# Install the host-matched NVIDIA userspace tools so containers get nvidia-smi
# and the driver-side CUDA libraries needed by the runtime.
ARG NVIDIA_DRIVER_BRANCH=560
RUN apt-get install -y --no-install-recommends \
    libnvidia-compute-${NVIDIA_DRIVER_BRANCH} \
    nvidia-compute-utils-${NVIDIA_DRIVER_BRANCH} \
    nvidia-utils-${NVIDIA_DRIVER_BRANCH}

# System-level initialization.
RUN ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    locale-gen C.UTF-8 && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    git lfs install --system && \
    mkdir -p /var/run/sshd

# Create the container user to match the host identity.
RUN if ! getent group "${LOCAL_GID}" >/dev/null; then \
        groupadd --gid "${LOCAL_GID}" "${LOCAL_USER}"; \
    fi && \
    if id -u "${LOCAL_USER}" >/dev/null 2>&1; then \
        usermod --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" --shell /bin/bash "${LOCAL_USER}"; \
    elif getent passwd "${LOCAL_UID}" >/dev/null; then \
        EXISTING_USER="$(getent passwd "${LOCAL_UID}" | cut -d: -f1)" && \
        usermod --login "${LOCAL_USER}" --home "/home/${LOCAL_USER}" --move-home --gid "${LOCAL_GID}" --shell /bin/bash "${EXISTING_USER}"; \
    else \
        useradd --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" --create-home --shell /bin/bash "${LOCAL_USER}"; \
    fi && \
    usermod -aG sudo "${LOCAL_USER}" && \
    echo "${LOCAL_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${LOCAL_USER}" && \
    chmod 0440 "/etc/sudoers.d/${LOCAL_USER}" && \
    mkdir -p /workspace && \
    chown "${LOCAL_UID}:${LOCAL_GID}" /workspace

# Minimal sshd hardening for key-based access to the development user.
RUN mkdir -p "/etc/ssh/sshd_config.d" "/home/${LOCAL_USER}/.ssh" && \
    printf '%s\n' \
        "PubkeyAuthentication yes" \
        "PasswordAuthentication no" \
        "KbdInteractiveAuthentication no" \
        "PermitRootLogin no" \
        "AllowUsers ${LOCAL_USER}" \
        "AuthorizedKeysFile .ssh/authorized_keys" \
        > "/etc/ssh/sshd_config.d/10-cuda-env.conf" && \
    chmod 0700 "/home/${LOCAL_USER}/.ssh" && \
    chown "${LOCAL_UID}:${LOCAL_GID}" "/home/${LOCAL_USER}/.ssh"

# Keep apt indexes around while package installation is still ongoing, then
# clean them once at the end so intermediate layers can reuse the metadata.
RUN rm -rf /var/lib/apt/lists/*

ENV LOCAL_USER=${LOCAL_USER} \
    GIT_USER=${GIT_USER} \
    GIT_EMAIL=${GIT_EMAIL} \
    DOTFILE_REPO_URL=${DOTFILE_REPO_URL} \
    CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION} \
    NVM_DIR=/home/${LOCAL_USER}/.nvm \
    CARGO_HOME=/home/${LOCAL_USER}/.cargo \
    RUSTUP_HOME=/home/${LOCAL_USER}/.rustup \
    UV_NO_MODIFY_PATH=1 \
    BASH_ENV=/home/${LOCAL_USER}/.bash_env \
    NVM_SYMLINK_CURRENT=true \
    PATH=/home/${LOCAL_USER}/.local/bin:/home/${LOCAL_USER}/.cargo/bin:/home/${LOCAL_USER}/.nvm/current/bin:/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}

# User shell bootstrap and reusable environment wiring.
RUN mkdir -p \
    "/home/${LOCAL_USER}/.local/bin" \
    "${NVM_DIR}" \
    "${CARGO_HOME}" \
    "${RUSTUP_HOME}" && \
    touch "${BASH_ENV}" && \
    for proxy_target in "${BASH_ENV}" "/home/${LOCAL_USER}/.bashrc"; do \
        for proxy_var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do \
            proxy_value="${!proxy_var:-}"; \
            if [[ -n "${proxy_value}" ]]; then \
                printf 'export %s=%q\n' "${proxy_var}" "${proxy_value}" >> "${proxy_target}"; \
            fi; \
        done; \
    done && \
    echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "${BASH_ENV}" && \
    echo 'export CUDA_HOME="/usr/local/cuda"' >> "${BASH_ENV}" && \
    echo 'export PATH="/usr/local/cuda/bin:$PATH"' >> "${BASH_ENV}" && \
    echo 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH:-}"' >> "${BASH_ENV}" && \
    echo 'export NVM_DIR="$HOME/.nvm"' >> "${BASH_ENV}" && \
    echo 'export CARGO_HOME="$HOME/.cargo"' >> "${BASH_ENV}" && \
    echo 'export RUSTUP_HOME="$HOME/.rustup"' >> "${BASH_ENV}" && \
    echo '[ -s "$CARGO_HOME/env" ] && . "$CARGO_HOME/env"' >> "${BASH_ENV}" && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> "${BASH_ENV}" && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' >> "${BASH_ENV}" && \
    echo '. "$BASH_ENV"' >> "/home/${LOCAL_USER}/.bashrc" && \
    chown -R "${LOCAL_UID}:${LOCAL_GID}" \
    "/home/${LOCAL_USER}/.local" \
    "${NVM_DIR}" \
    "${CARGO_HOME}" \
    "${RUSTUP_HOME}" && \
    chown "${LOCAL_UID}:${LOCAL_GID}" "${BASH_ENV}" && \
    chown "${LOCAL_UID}:${LOCAL_GID}" "/home/${LOCAL_USER}/.bashrc"

USER ${LOCAL_USER}
WORKDIR /workspace

# User-level Git defaults.
RUN git config --global user.name "${GIT_USER}" && \
    git config --global user.email "${GIT_EMAIL}" && \
    git config --global init.defaultBranch main && \
    git config --global core.editor nano && \
    git config --global pull.rebase false

# Personal shell dotfiles. Avoid the repo's interactive install flow in Docker.
RUN git clone "${DOTFILE_REPO_URL}" "${HOME}/.dotfile" && \
    bash "${HOME}/.dotfile/bashrc_common.sh" refresh-region && \
    source "${HOME}/.dotfile/bashrc_common.sh" && \
    dotfile_apply_key_changes && \
    if ! grep -qF 'source "$HOME/.dotfile/bashrc_common.sh"' "${HOME}/.bashrc"; then \
        printf '\nsource "$HOME/.dotfile/bashrc_common.sh"\n' >> "${HOME}/.bashrc"; \
    fi && \
    if ! grep -qF 'source "$HOME/.dotfile/bashrc_common.sh"' "${BASH_ENV}"; then \
        printf '\nsource "$HOME/.dotfile/bashrc_common.sh"\n' >> "${BASH_ENV}"; \
    fi

# Node runtime via nvm.
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE="${BASH_ENV}" bash && \
    source "${BASH_ENV}" && \
    nvm install "${NODE_VERSION}" && \
    nvm alias default "${NODE_VERSION}" && \
    nvm use default

# Rust toolchain and source-built TUI tools.
ARG ZELLIJ_VERSION=v0.44.0
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable && \
    source "${BASH_ENV}" && \
    cargo install --locked --version "${ZELLIJ_VERSION#v}" zellij && \
    cargo install --locked yazi-fm yazi-cli && \
    zellij --version && \
    yazi --version

# Python-adjacent developer tooling managed by uv.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    source "${BASH_ENV}" && \
    uv tool install nvidia-htop

# Node-based CLI tools.
RUN source "${BASH_ENV}" && \
    npm install -g @openai/codex && \
    if [[ -n "${CODEX_CONFIG_ARCHIVE_B64:-}" ]]; then \
        mkdir -p "${HOME}/.codex" && \
        printf '%s' "${CODEX_CONFIG_ARCHIVE_B64}" | \
            base64 -d | \
            tar -xzf - -C "${HOME}" && \
        find "${HOME}/.codex" -type d -exec chmod 0700 {} + && \
        find "${HOME}/.codex" -type f -exec chmod 0600 {} +; \
    fi

# Claude Code native installer.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

EXPOSE 22

CMD ["/bin/bash"]

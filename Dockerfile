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
ARG DEV_SECRETS_ARCHIVE_B64
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
    gh \
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
    zsh \
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

# Install Docker CLI tooling so the container can target the host engine through
# a mounted Docker socket.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    . /etc/os-release && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin

# Install the host-matched NVIDIA userspace tools so containers get nvidia-smi
# and the driver-side CUDA libraries needed by the runtime.
ARG NVIDIA_DRIVER_BRANCH
RUN if [[ -n "${NVIDIA_DRIVER_BRANCH:-}" ]]; then \
        apt-get install -y --no-install-recommends \
        libnvidia-compute-${NVIDIA_DRIVER_BRANCH} \
        nvidia-compute-utils-${NVIDIA_DRIVER_BRANCH} \
        nvidia-utils-${NVIDIA_DRIVER_BRANCH}; \
    else \
        echo "Skipping NVIDIA userspace package install because NVIDIA_DRIVER_BRANCH is empty."; \
    fi

# System-level initialization.
RUN ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    locale-gen C.UTF-8 && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    git lfs install --system && \
    mkdir -p /var/run/sshd

# Create the container user to match the host identity.
RUN if [[ "${LOCAL_UID}" == "0" && "${LOCAL_GID}" == "0" && "${LOCAL_USER}" != "root" ]]; then \
        if id -u "${LOCAL_USER}" >/dev/null 2>&1; then \
            usermod --non-unique --uid 0 --gid 0 --home "/home/${LOCAL_USER}" --move-home --shell /usr/bin/zsh "${LOCAL_USER}"; \
        else \
            useradd --non-unique --uid 0 --gid 0 --create-home --home-dir "/home/${LOCAL_USER}" --shell /usr/bin/zsh "${LOCAL_USER}"; \
        fi; \
    else \
        if ! getent group "${LOCAL_GID}" >/dev/null; then \
            groupadd --gid "${LOCAL_GID}" "${LOCAL_USER}"; \
        fi; \
        if id -u "${LOCAL_USER}" >/dev/null 2>&1; then \
            usermod --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" --shell /usr/bin/zsh "${LOCAL_USER}"; \
        elif getent passwd "${LOCAL_UID}" >/dev/null; then \
            EXISTING_USER="$(getent passwd "${LOCAL_UID}" | cut -d: -f1)" && \
            usermod --login "${LOCAL_USER}" --home "/home/${LOCAL_USER}" --move-home --gid "${LOCAL_GID}" --shell /usr/bin/zsh "${EXISTING_USER}"; \
        else \
            useradd --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" --create-home --shell /usr/bin/zsh "${LOCAL_USER}"; \
        fi; \
    fi && \
    usermod -aG sudo "${LOCAL_USER}" && \
    echo "${LOCAL_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${LOCAL_USER}" && \
    chmod 0440 "/etc/sudoers.d/${LOCAL_USER}" && \
    mkdir -p /workspace "/home/${LOCAL_USER}/.ssh" && \
    chmod 0700 "/home/${LOCAL_USER}/.ssh" && \
    chown "${LOCAL_UID}:${LOCAL_GID}" "/home/${LOCAL_USER}/.ssh" && \
    chown "${LOCAL_UID}:${LOCAL_GID}" /workspace

# Minimal sshd hardening for key-based access to the development user.
RUN mkdir -p "/etc/ssh/sshd_config.d" && \
    permit_root_login="no" && \
    if [[ "${LOCAL_UID}" == "0" ]]; then \
        permit_root_login="prohibit-password"; \
    fi && \
    printf '%s\n' \
        "PubkeyAuthentication yes" \
        "PasswordAuthentication no" \
        "KbdInteractiveAuthentication no" \
        "PermitRootLogin ${permit_root_login}" \
        "AllowUsers ${LOCAL_USER}" \
        "AuthorizedKeysFile .ssh/authorized_keys" \
        > "/etc/ssh/sshd_config.d/10-cuda-env.conf"

# Keep apt indexes around while package installation is still ongoing, then
# clean them once at the end so intermediate layers can reuse the metadata.
RUN rm -rf /var/lib/apt/lists/*

ENV LOCAL_USER=${LOCAL_USER} \
    GIT_USER=${GIT_USER} \
    GIT_EMAIL=${GIT_EMAIL} \
    DOTFILE_REPO_URL=${DOTFILE_REPO_URL} \
    HOME=/home/${LOCAL_USER} \
    SHELL=/usr/bin/zsh \
    DEV_SHELL_ENV=/home/${LOCAL_USER}/.shell_env \
    NVM_DIR=/home/${LOCAL_USER}/.nvm \
    CARGO_HOME=/home/${LOCAL_USER}/.cargo \
    RUSTUP_HOME=/home/${LOCAL_USER}/.rustup \
    UV_NO_MODIFY_PATH=1 \
    BASH_ENV=/home/${LOCAL_USER}/.shell_env \
    NVM_SYMLINK_CURRENT=true \
    PATH=/home/${LOCAL_USER}/.local/bin:/home/${LOCAL_USER}/.cargo/bin:/home/${LOCAL_USER}/.nvm/current/bin:/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}

USER ${LOCAL_USER}
WORKDIR /workspace

# User shell bootstrap and reusable environment wiring shared by bash and zsh.
RUN mkdir -p \
    "$HOME/.local/bin" \
    "${NVM_DIR}" \
    "${CARGO_HOME}" \
    "${RUSTUP_HOME}" \
    "$HOME/.ssh" && \
    chmod 0700 "$HOME/.ssh" && \
    touch "${DEV_SHELL_ENV}" && \
    printf '%s\n' \
        'if [[ -n "${DEV_SHELL_ENV_LOADED:-}" ]]; then' \
        '    return 0' \
        'fi' \
        'DEV_SHELL_ENV_LOADED=1' \
        '' \
        'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' \
        'export CUDA_HOME="/usr/local/cuda"' \
        'export PATH="/usr/local/cuda/bin:$PATH"' \
        'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH:-}"' \
        'export NVM_DIR="$HOME/.nvm"' \
        'export CARGO_HOME="$HOME/.cargo"' \
        'export RUSTUP_HOME="$HOME/.rustup"' \
        '[ -s "$CARGO_HOME/env" ] && . "$CARGO_HOME/env"' \
        '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' \
        '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' \
        > "${DEV_SHELL_ENV}" && \
    for proxy_var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do \
        proxy_value="${!proxy_var:-}"; \
        if [[ -n "${proxy_value}" ]]; then \
            printf 'export %s=%q\n' "${proxy_var}" "${proxy_value}" >> "${DEV_SHELL_ENV}"; \
        fi; \
    done && \
    printf '%s\n' \
        '[ -f "$HOME/.shell_env" ] && . "$HOME/.shell_env"' \
        > "$HOME/.bashrc" && \
    printf '%s\n' \
        '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' \
        > "$HOME/.bash_profile" && \
    printf '%s\n' \
        '[ -f "$HOME/.shell_env" ] && source "$HOME/.shell_env"' \
        > "$HOME/.zprofile" && \
    printf '%s\n' \
        'export ZSH="$HOME/.oh-my-zsh"' \
        'ZSH_THEME="robbyrussell"' \
        'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' \
        '' \
        '[ -f "$HOME/.shell_env" ] && source "$HOME/.shell_env"' \
        '[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"' \
        > "$HOME/.zshrc"

# User-level Git defaults.
RUN git config --global user.name "${GIT_USER}" && \
    git config --global user.email "${GIT_EMAIL}" && \
    git config --global init.defaultBranch main && \
    git config --global core.editor nano && \
    git config --global pull.rebase false

# Personal shell dotfiles. Reuse the repo's non-interactive install entrypoint
# while keeping sshd managed by this image and letting dotfile manage
# authorized_keys.
RUN git clone "${DOTFILE_REPO_URL}" "${HOME}/.dotfile" && \
    bash "${HOME}/.dotfile/bashrc_common.sh" install -y --ssh-keys=apply --sshd=skip

# Install and wire up Oh My Zsh without changing shell interactively.
RUN RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

# Node runtime via nvm. nvm refuses to run while npm's global prefix is set,
# so temporarily clear it and source nvm directly from NVM_DIR.
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE="${BASH_ENV}" bash && \
    tmp_bash_env="$(mktemp)" && \
    if [[ -f "${DEV_SHELL_ENV}" ]]; then \
        grep -E '^(export (http_proxy|https_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|NO_PROXY)=)' "${DEV_SHELL_ENV}" > "${tmp_bash_env}" || true; \
    fi && \
    unset NPM_CONFIG_PREFIX npm_config_prefix && \
    export NVM_DIR="${NVM_DIR}" && \
    export BASH_ENV="${tmp_bash_env}" && \
    . "${NVM_DIR}/nvm.sh" && \
    nvm install "${NODE_VERSION}" && \
    nvm alias default "${NODE_VERSION}" && \
    nvm use default && \
    rm -f "${tmp_bash_env}"

# Rust toolchain and source-built TUI tools.
ARG ZELLIJ_VERSION=v0.44.0
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable && \
    . "${CARGO_HOME}/env" && \
    cargo install --locked --version "${ZELLIJ_VERSION#v}" zellij && \
    cargo install --force yazi-build && \
    zellij --version && \
    yazi --version

# Python-adjacent developer tooling managed by uv.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    source "${BASH_ENV}" && \
    uv tool install nvidia-htop

# Claude Code official installer.
RUN source "${BASH_ENV}" && \
    curl -fsSL https://claude.ai/install.sh | bash

# Node-based CLI tools and optional host secrets import.
RUN source "${BASH_ENV}" && \
    npm install -g @openai/codex && \
    if [[ -n "${DEV_SECRETS_ARCHIVE_B64:-}" ]]; then \
        tmpdir="$(mktemp -d)" && \
        printf '%s' "${DEV_SECRETS_ARCHIVE_B64}" | \
            base64 -d | \
            tar -xzf - -C "${tmpdir}" && \
        if [[ -d "${tmpdir}/.dev-secrets/claude" ]]; then \
            mkdir -p "${HOME}/.claude" && \
            cp -a "${tmpdir}/.dev-secrets/claude/." "${HOME}/.claude/"; \
            find "${HOME}/.claude" -type d -exec chmod 0700 {} +; \
            find "${HOME}/.claude" -type f -exec chmod 0600 {} +; \
        fi && \
        if [[ -d "${tmpdir}/.dev-secrets/codex" ]]; then \
            mkdir -p "${HOME}/.codex" && \
            cp -a "${tmpdir}/.dev-secrets/codex/." "${HOME}/.codex/"; \
            find "${HOME}/.codex" -type d -exec chmod 0700 {} +; \
            find "${HOME}/.codex" -type f -exec chmod 0600 {} +; \
        fi && \
        if [[ -d "${tmpdir}/.dev-secrets/ssh" ]]; then \
            mkdir -p "${HOME}/.ssh" && \
            cp -a "${tmpdir}/.dev-secrets/ssh/." "${HOME}/.ssh/"; \
            find "${HOME}/.ssh" -type d -exec chmod 0700 {} +; \
            find "${HOME}/.ssh" -type f -exec chmod 0600 {} +; \
        fi && \
        if [[ -f "${tmpdir}/.dev-secrets/github/gh_token" ]]; then \
            mkdir -p "${HOME}/.config/gh" && \
            chmod 0700 "${HOME}/.config" "${HOME}/.config/gh" && \
            gh auth login --hostname github.com --with-token < "${tmpdir}/.dev-secrets/github/gh_token" && \
            find "${HOME}/.config/gh" -type d -exec chmod 0700 {} + && \
            find "${HOME}/.config/gh" -type f -exec chmod 0600 {} +; \
        fi && \
        if [[ -f "${tmpdir}/.dev-secrets/huggingface/token" ]]; then \
            mkdir -p "${HOME}/.cache/huggingface" && \
            chmod 0700 "${HOME}/.cache" "${HOME}/.cache/huggingface" && \
            cp "${tmpdir}/.dev-secrets/huggingface/token" "${HOME}/.cache/huggingface/token" && \
            chmod 0600 "${HOME}/.cache/huggingface/token"; \
        fi && \
        rm -rf "${tmpdir}"; \
    fi

EXPOSE 22

CMD ["sudo", "/usr/sbin/sshd", "-D", "-e"]

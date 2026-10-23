# syntax=docker/dockerfile:1.7
#
# AI sandbox: Debian-based Node image with Claude Code, OpenCode,
# GitHub Copilot CLI and common developer/debugging tools.
#
# At runtime it runs exclusively as the unprivileged user "dev",
# without sudo, without capabilities, with a read-only root filesystem.
# Packages are installed ONLY here (or in the sub-images) via apt.

ARG BASE_IMAGE=node:lts-bookworm-slim
FROM ${BASE_IMAGE}

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
# "latest" or pinned versions, e.g. CLAUDE_CODE_VERSION=2.1.309
ARG CLAUDE_CODE_VERSION=latest
ARG OPENCODE_VERSION=latest
ARG COPILOT_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Berlin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- Base, developer and debugging tools ------------------------------------
# Packages that are not available on every architecture (e.g. ltrace is
# missing on arm64) are listed in the for loop and installed only if present.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash bash-completion ca-certificates curl wget gnupg \
      git git-lfs openssh-client \
      build-essential make cmake pkg-config \
      python3 python3-pip python3-venv \
      jq yq ripgrep fd-find fzf tree less file bat \
      vim-tiny nano tmux htop procps psmisc lsof strace gdb \
      iproute2 dnsutils netcat-openbsd socat telnet \
      zip unzip xz-utils zstd rsync patch diffutils \
      shellcheck sqlite3 man-db locales tzdata \
 && for p in ltrace; do \
      if apt-cache show "$p" >/dev/null 2>&1; then apt-get install -y --no-install-recommends "$p"; \
      else echo "Package $p not available for $(dpkg --print-architecture), skipped"; fi; \
    done \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && ln -sf /usr/bin/batcat /usr/local/bin/bat \
 && rm -rf /var/lib/apt/lists/*

# --- GitHub CLI (official apt repository) -----------------------------------
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# --- AI harnesses (global, root-owned -> cannot be tampered with at runtime) -
RUN npm install -g --omit=dev \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
      "@github/copilot@${COPILOT_VERSION}" \
 && npm cache clean --force \
 && claude --version && opencode --version && copilot --version

# --- Unprivileged user -------------------------------------------------------
# The node image ships a "node" user (1000:1000); rename it and adjust
# UID/GID so bind mounts from the Mac get matching permissions.
RUN groupmod -n "${USERNAME}" node \
 && usermod -l "${USERNAME}" -d "/home/${USERNAME}" -m node \
 && groupmod -g "${USER_GID}" "${USERNAME}" \
 && usermod -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USERNAME}" \
 && install -d -o "${USER_UID}" -g "${USER_GID}" \
      "/home/${USERNAME}/.claude" \
      "/home/${USERNAME}/.copilot" \
      "/home/${USERNAME}/.config/opencode" \
      "/home/${USERNAME}/.local/share" \
      "/home/${USERNAME}/.local/bin" \
      "/home/${USERNAME}/.cache" \
      /workspace \
 && chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}"

# git: GitHub auth via GH_TOKEN/GITHUB_TOKEN, with gh as credential helper
COPY gitconfig /etc/gitconfig
COPY bashrc.sandbox /etc/bash.sandbox.sh
RUN echo '. /etc/bash.sandbox.sh' >> /etc/bash.bashrc

COPY --chmod=0755 entrypoint.sh /usr/local/bin/sandbox-entrypoint
COPY --chmod=0755 sandbox-doctor.sh /usr/local/bin/sandbox-doctor

ENV HOME=/home/${USERNAME} \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude \
    DISABLE_AUTOUPDATER=1 \
    NODE_USE_ENV_PROXY=1 \
    EDITOR=vim.tiny \
    PATH=/home/${USERNAME}/.local/bin:${PATH}

USER ${USERNAME}
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
CMD ["sleep", "infinity"]

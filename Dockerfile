FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        jq \
        ripgrep \
        ca-certificates \
        gnupg \
        openssh-client \
        python3 \
        unzip \
        sudo \
        buildah \
        skopeo \
        crun \
    && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI ───────────────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ── yq (YAML parser) ────────────────────────────────────────────────────────
ARG YQ_VERSION=v4.44.1
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# ── Node.js 20.x LTS (required by Claude Code) ─────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ───────────────────────────────────────────────────────────
# Ubuntu 24.04 has a default 'ubuntu' user at UID 1000; remove it first
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/claude

USER claude
ENV HOME=/home/claude
WORKDIR /tmp

# ── Claude Code ──────────────────────────────────────────────────────────────
RUN curl -fsSL https://claude.ai/install.sh | bash

# ── Directories ──────────────────────────────────────────────────────────────
RUN mkdir -p /home/claude/.claude \
             /home/claude/.claude/agents \
             /home/claude/.claude/skills \
             /home/claude/.claude/plugins


USER root

# ── Buildah: system-level container config (runs as root via sudo) ────────
# Rootless Buildah fails inside containers (newuidmap/newgidmap can't create
# user namespaces). The docker shim uses sudo, so config goes to /etc/containers/.
COPY containers-config/storage.conf /etc/containers/storage.conf
COPY containers-config/registries.conf /etc/containers/registries.conf
COPY containers-config/containers.conf /etc/containers/containers.conf

# ── Copy scripts and config ─────────────────────────────────────────────────
COPY --chown=claude:claude scripts/   /scripts/
COPY --chown=claude:claude claude-config/ /etc/claude-sandbox/claude-config/
COPY --chown=claude:claude templates/ /etc/claude-sandbox/templates/

RUN chmod +x /scripts/*.sh

# ── Docker shim (maps docker CLI to Buildah) ──────────────────────────────
COPY --chown=root:root scripts/docker-shim.sh /usr/local/bin/docker
RUN chmod +x /usr/local/bin/docker

# ── Environment ──────────────────────────────────────────────────────────────
ENV DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    TERM=xterm-256color \
    PATH="/home/claude/.local/bin:${PATH}"

USER claude
WORKDIR /workspace

ENTRYPOINT ["/scripts/entrypoint.sh"]

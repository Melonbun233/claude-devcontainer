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
             /home/claude/.claude/skills

USER root

# ── Copy scripts and config ─────────────────────────────────────────────────
COPY --chown=claude:claude scripts/   /scripts/
COPY --chown=claude:claude jira-cli/  /usr/local/lib/jira-cli/
COPY --chown=claude:claude claude-config/ /etc/claude-dev/claude-config/
COPY --chown=claude:claude templates/ /etc/claude-dev/templates/

RUN chmod +x /scripts/*.sh /scripts/modes/*.sh \
    && for f in /usr/local/lib/jira-cli/*.sh; do \
         name="$(basename "$f" .sh)"; \
         ln -sf "$f" "/usr/local/bin/$name"; \
         chmod +x "$f"; \
       done

# ── Environment ──────────────────────────────────────────────────────────────
ENV DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    TERM=xterm-256color \
    PATH="/home/claude/.local/bin:${PATH}"

USER claude
WORKDIR /workspace

ENTRYPOINT ["/scripts/entrypoint.sh"]

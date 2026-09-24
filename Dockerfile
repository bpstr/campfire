FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/campfire
ENV PATH=/home/campfire/.local/bin:/usr/local/bin:/usr/bin:/bin
ENV CODEX_HOME=/home/campfire/.codex
ENV GROK_HOME=/home/campfire/.grok
ENV KIMI_CODE_HOME=/home/campfire/.kimi-code
ENV XDG_CONFIG_HOME=/home/campfire/.config
ENV XDG_DATA_HOME=/home/campfire/.local/share

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq python3 python3-pip nodejs npm tini coreutils \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex @anthropic-ai/claude-code @google/gemini-cli @moonshot-ai/kimi-code @xai-official/grok || true

RUN curl -fsSL https://dev.meta.ai/install.sh | bash || true

RUN useradd --create-home --uid 1000 --shell /bin/bash campfire \
    && mkdir -p /opt/campfire/agents /opt/campfire/defaults /opt/campfire/templates \
        /opt/campfire/mcp/providers /var/log/campfire \
        /home/campfire/.codex /home/campfire/.claude /home/campfire/.gemini \
        /home/campfire/.grok /home/campfire/.kimi-code \
        /home/campfire/.config /home/campfire/.local/share \
    && chown -R root:root /opt/campfire \
    && chown -R campfire:campfire /home/campfire /var/log/campfire

COPY mcp/package.json /opt/campfire/mcp/package.json
RUN cd /opt/campfire/mcp && npm install --omit=dev

COPY lib/lib.sh /opt/campfire/lib.sh
COPY agents/ /opt/campfire/agents/
COPY mcp/server.mjs /opt/campfire/mcp/server.mjs
COPY mcp/providers/ /opt/campfire/mcp/providers/
COPY templates/CAMPFIRE_AGENTS.md /opt/campfire/templates/CAMPFIRE_AGENTS.md
COPY research/README.md /opt/campfire/defaults/README.md
COPY bin/campfire-agents /usr/local/bin/campfire-agents
COPY bin/campfire-assist /usr/local/bin/campfire-assist
COPY bin/campfire-configure-mcp /usr/local/bin/campfire-configure-mcp
COPY controller.sh /usr/local/bin/campfire-controller

RUN chmod 0555 /opt/campfire/lib.sh /opt/campfire/agents/*.sh \
        /usr/local/bin/campfire-agents /usr/local/bin/campfire-assist \
        /usr/local/bin/campfire-configure-mcp /usr/local/bin/campfire-controller \
    && chmod 0444 /opt/campfire/templates/CAMPFIRE_AGENTS.md \
        /opt/campfire/defaults/README.md /opt/campfire/mcp/providers/*

USER campfire
WORKDIR /home/campfire
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/campfire-controller"]

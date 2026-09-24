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

RUN npm install -g @openai/codex @anthropic-ai/claude-code @google/gemini-cli @moonshot-ai/kimi-code || true\n\nCOPY mcp/package.json /opt/campfire/mcp/package.json\nRUN cd /opt/campfire/mcp && npm install --omit=dev

# Grok, Muse and Kimi installation paths are intentionally kept separate from
# Campfire's controller. Add/pin their supported installers here as needed.
# A CLI is only considered a participant when both its credential exists and
# its adapter is executable.

RUN useradd --create-home --uid 1000 --shell /bin/bash campfire \
    && mkdir -p /opt/campfire/agents /opt/campfire/defaults /opt/campfire/templates /var/log/campfire \
        /home/campfire/.codex /home/campfire/.claude /home/campfire/.gemini \
        /home/campfire/.grok /home/campfire/.kimi-code \
        /home/campfire/.config /home/campfire/.local/share \
    && chown -R root:root /opt/campfire \
    && chown -R campfire:campfire /home/campfire /var/log/campfire

COPY lib/lib.sh /opt/campfire/lib.sh\nCOPY mcp/server.mjs /opt/campfire/mcp/server.mjs\nCOPY mcp/campfire-mcp.json /opt/campfire/mcp/campfire-mcp.json\nCOPY bin/campfire-assist /usr/local/bin/campfire-assist
COPY agents/ /opt/campfire/agents/
COPY templates/CAMPFIRE_AGENTS.md /opt/campfire/templates/CAMPFIRE_AGENTS.md
COPY research/README.md /opt/campfire/defaults/README.md
COPY bin/campfire-agents /usr/local/bin/campfire-agents
COPY controller.sh /usr/local/bin/campfire-controller

RUN chmod 0555 /opt/campfire/lib.sh /opt/campfire/agents/*.sh \
    /usr/local/bin/campfire-agents /usr/local/bin/campfire-controller \
    && chmod 0444 /opt/campfire/templates/CAMPFIRE_AGENTS.md /opt/campfire/defaults/README.md

USER campfire
WORKDIR /home/campfire

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/campfire-controller"]

# API for Cursor: Bun serves the OpenAI-compatible HTTP API, and Node runs the
# Cursor SDK bridge. Bun's node:http2 client cannot speak the SDK's gRPC
# (NGHTTP2_FRAME_SIZE_ERROR), so both runtimes are required.
#
#   docker build -t api-for-cursor .
#   docker run --rm -p 8787:8787 api-for-cursor

FROM oven/bun:1.3.14-debian AS bun

FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends tini \
  && rm -rf /var/lib/apt/lists/*

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

WORKDIR /app

RUN chown node:node /app

COPY --chown=node:node package.json bun.lock ./

USER node

RUN bun install --frozen-lockfile --production

COPY --chown=node:node server.ts ./server.ts
COPY --chown=node:node worker ./worker
COPY --chown=node:node scripts/cursor-sdk-local-agent-bridge.mjs ./scripts/cursor-sdk-local-agent-bridge.mjs

# Listen on all interfaces so published ports reach the server. The SDK bridge
# stays on 127.0.0.1 inside the container.
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8787 \
    CURSOR_SDK_BRIDGE_RUNTIME=node

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bun", "server.ts"]

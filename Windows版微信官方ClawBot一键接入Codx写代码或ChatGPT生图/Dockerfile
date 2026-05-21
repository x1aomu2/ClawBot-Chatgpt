FROM node:22-bookworm-slim

ARG CC_CONNECT_PACKAGE=cc-connect@beta
ARG NPM_REGISTRY=

ENV NODE_ENV=production \
    APP_ROOT=/app \
    ROUTER_CC_CONNECT_CMD=cc-connect \
    ROUTER_DATA_DIR=/app/.router-data \
    ROUTER_PROJECT_NAME=test

WORKDIR /app

RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi \
  && npm install -g "$CC_CONNECT_PACKAGE" \
  && npm cache clean --force

COPY . /app

ENTRYPOINT ["sh", "/app/docker-entrypoint.sh"]
CMD ["start"]

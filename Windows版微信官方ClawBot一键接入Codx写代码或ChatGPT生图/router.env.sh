#!/usr/bin/env sh

ROOT_DIR=${ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
LOCAL_ENV_FILE=${ROUTER_LOCAL_ENV_FILE:-"$ROOT_DIR/.router-data/router.env.local.sh"}

if [ -f "$LOCAL_ENV_FILE" ]; then
  # Generated values use default-only assignments, so non-empty Docker env wins.
  # shellcheck disable=SC1091
  . "$LOCAL_ENV_FILE"
fi

if [ -z "${ROUTER_DATA_DIR:-}" ]; then
  ROUTER_DATA_DIR="$ROOT_DIR/.router-data"
  export ROUTER_DATA_DIR
fi

if [ -z "${ROUTER_ROUTE_CONFIG_FILE:-}" ]; then
  ROUTER_ROUTE_CONFIG_FILE="$ROUTER_DATA_DIR/config.route.toml"
  export ROUTER_ROUTE_CONFIG_FILE
fi

if [ -z "${ROUTER_WEIXIN_SETUP_CONFIG:-}" ]; then
  ROUTER_WEIXIN_SETUP_CONFIG="$ROUTER_DATA_DIR/.weixin-setup.toml"
  export ROUTER_WEIXIN_SETUP_CONFIG
fi

if [ -z "${ROUTER_WEIXIN_QR_IMAGE:-}" ]; then
  ROUTER_WEIXIN_QR_IMAGE="$ROUTER_DATA_DIR/weixin-qr.png"
  export ROUTER_WEIXIN_QR_IMAGE
fi

if [ -z "${ROUTER_LOCAL_ENV_FILE:-}" ]; then
  ROUTER_LOCAL_ENV_FILE="$ROUTER_DATA_DIR/router.env.local.sh"
  export ROUTER_LOCAL_ENV_FILE
fi

if [ -z "${ROUTER_STATE_FILE:-}" ]; then
  ROUTER_STATE_FILE="$ROUTER_DATA_DIR/.cc-router-state.json"
  export ROUTER_STATE_FILE
fi

if [ -z "${ROUTER_DECISION_LOG_FILE:-}" ]; then
  ROUTER_DECISION_LOG_FILE="$ROUTER_DATA_DIR/.cc-router-decisions.log"
  export ROUTER_DECISION_LOG_FILE
fi

if [ -z "${ROUTER_CACHE_DIR:-}" ]; then
  ROUTER_CACHE_DIR="$ROUTER_DATA_DIR/.cc-router-cache"
  export ROUTER_CACHE_DIR
fi

if [ -z "${ROUTER_CC_CONNECT_CMD:-}" ]; then
  ROUTER_CC_CONNECT_CMD=cc-connect
  export ROUTER_CC_CONNECT_CMD
fi

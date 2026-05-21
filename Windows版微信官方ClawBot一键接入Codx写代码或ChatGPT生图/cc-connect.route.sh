#!/usr/bin/env sh
set -eu

ROOT_DIR=${ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
export ROOT_DIR

# shellcheck disable=SC1091
. "$ROOT_DIR/router.env.sh"

ROUTE_CONFIG=${ROUTER_ROUTE_CONFIG_FILE:-"$ROOT_DIR/.router-data/config.route.toml"}

exec "$ROUTER_CC_CONNECT_CMD" --config "$ROUTE_CONFIG" --force

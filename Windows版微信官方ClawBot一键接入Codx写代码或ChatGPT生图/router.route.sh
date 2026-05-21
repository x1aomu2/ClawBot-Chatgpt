#!/usr/bin/env sh
set -eu

ROOT_DIR=${ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
export ROOT_DIR

# shellcheck disable=SC1091
. "$ROOT_DIR/router.env.sh"

exec node "$ROOT_DIR/router.mjs" agent "$@"

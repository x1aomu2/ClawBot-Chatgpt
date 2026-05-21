#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi

  echo "Docker Compose was not found. Install Docker Desktop or docker compose first." >&2
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker was not found. Install Docker Desktop or Docker Engine first." >&2
  exit 1
fi

mkdir -p .router-data

if [ ! -f .env ] && [ ! -f .router-data/router.env.local.sh ]; then
  echo "Tip: create .env from .env.example before the first real run." >&2
fi

case "${1:-up}" in
  up|start)
    compose up -d --build
    ;;
  restart)
    compose up -d --build --force-recreate
    ;;
  logs)
    compose logs -f router
    ;;
  stop|down)
    compose down
    ;;
  status|ps)
    compose ps
    ;;
  shell)
    compose exec router sh
    ;;
  *)
    echo "Usage: sh deploy.sh [up|restart|logs|stop|status|shell]" >&2
    exit 2
    ;;
esac

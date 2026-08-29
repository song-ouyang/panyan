#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${WANPAN_ENV_FILE:-.env.production}"
COMPOSE_FILE="${1:-${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "未找到 Docker Compose。" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "缺少 $ROOT_DIR/$ENV_FILE" >&2
  exit 1
fi

mkdir -p backups
chmod 700 backups
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET="backups/wanpan-$STAMP.sql.gz"
umask 077
"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  sh -ec 'exec pg_dump --clean --if-exists --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  | gzip -9 > "$TARGET"
gzip -t "$TARGET"
find backups -name 'wanpan-*.sql.gz' -mtime +14 -delete
echo "备份完成: $TARGET"

#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${WANPAN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ENV_FILE="${WANPAN_ENV_FILE:-$ROOT_DIR/.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"

if [[ "${ALLOW_PRODUCTION_SQUARE_COMMENT_CLEANUP:-false}" != "true" ]]; then
  echo "请为本次清理命令传入 ALLOW_PRODUCTION_SQUARE_COMMENT_CLEANUP=true。" >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "未找到 Docker Compose。" >&2
  exit 1
fi

cd "$ROOT_DIR"
bash deploy/check-production-env.sh "$ENV_FILE"
WANPAN_ENV_FILE="$ENV_FILE" bash deploy/backup.sh "$COMPOSE_FILE" </dev/null

"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  sh -ec 'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < "$SCRIPT_DIR/remove-square-mock-comments.sql"

curl -fsS --max-time 5 http://127.0.0.1:3100/health >/dev/null
curl -fsS --max-time 5 http://127.0.0.1:3100/ready >/dev/null
echo "历史模拟评论清理完成，API 存活与数据库就绪检查均通过。"

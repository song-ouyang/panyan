#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
ENV_FILE="${WANPAN_ENV_FILE:-.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"
cd "$ROOT_DIR"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "未找到 Docker Compose。" >&2
  exit 1
fi

previous="${1:-$(cat .deploy/previous-image-tag 2>/dev/null || true)}"
current="$(cat .deploy/current-image-tag 2>/dev/null || true)"
if [[ -z "$previous" ]]; then
  echo "没有可回滚的上一镜像标签。" >&2
  exit 1
fi
if ! docker image inspect "wanpan-diary-api:$previous" >/dev/null 2>&1; then
  echo "本机不存在镜像 wanpan-diary-api:$previous，无法回滚。" >&2
  exit 1
fi

echo "回滚前备份数据库……"
WANPAN_ENV_FILE="$ENV_FILE" bash deploy/backup.sh "$COMPOSE_FILE"
API_IMAGE_TAG="$previous" "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build

api_id="$(API_IMAGE_TAG="$previous" "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q api)"
for _ in $(seq 1 60); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$api_id" 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  sleep 2
done
if [[ "${status:-}" != "healthy" ]]; then
  "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs --tail=120 api >&2 || true
  echo "回滚镜像未能健康启动。" >&2
  exit 1
fi

printf '%s\n' "$previous" > .deploy/current-image-tag
[[ -n "$current" ]] && printf '%s\n' "$current" > .deploy/previous-image-tag
chmod 600 .deploy/*
echo "API 已回滚到镜像 $previous。数据库未回退；如需恢复数据，请人工确认后使用 backups/ 中的备份。"

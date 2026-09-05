#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
ENV_FILE="${WANPAN_ENV_FILE:-$ROOT_DIR/.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"

if [[ "${ALLOW_PRODUCTION_SQUARE_SEED:-false}" != "true" ]]; then
  echo "错误：生产广场体验数据导入需要为本次命令显式传入 ALLOW_PRODUCTION_SQUARE_SEED=true。" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误：找不到 $ENV_FILE" >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "错误：未找到 Docker Compose。" >&2
  exit 1
fi

cd "$ROOT_DIR"
bash deploy/check-production-env.sh "$ENV_FILE"

image_tag="${API_IMAGE_TAG:-$(cat .deploy/current-image-tag 2>/dev/null || true)}"
if [[ -z "$image_tag" ]]; then
  echo "错误：找不到当前 API 镜像版本，请先完成一次生产部署。" >&2
  exit 1
fi
if ! docker image inspect "wanpan-diary-api:$image_tag" >/dev/null 2>&1; then
  echo "错误：本机不存在当前 API 镜像 wanpan-diary-api:$image_tag。" >&2
  exit 1
fi

api_container_id="$(
  API_IMAGE_TAG="$image_tag" "${COMPOSE[@]}" \
    --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q api
)"
if [[ -z "$api_container_id" ]]; then
  echo "错误：当前没有正在运行的 API 容器，请先完成生产部署。" >&2
  exit 1
fi
expected_image_id="$(docker image inspect --format '{{.Id}}' "wanpan-diary-api:$image_tag")"
running_image_id="$(docker inspect --format '{{.Image}}' "$api_container_id")"
if [[ "$running_image_id" != "$expected_image_id" ]]; then
  echo "错误：当前运行中的 API 容器与版本 $image_tag 不一致，请先重新部署。" >&2
  exit 1
fi

bash deploy/backup.sh "$COMPOSE_FILE"

API_IMAGE_TAG="$image_tag" "${COMPOSE[@]}" \
  --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
  run --rm --no-deps --pull never \
  -e NODE_ENV=production \
  -e ALLOW_PRODUCTION_SQUARE_SEED=true \
  api sh -c 'node server/dist/db/migrate.js && node server/dist/db/seed_square_experience.js'

curl -fsS --max-time 5 http://127.0.0.1:3100/health >/dev/null
curl -fsS --max-time 5 http://127.0.0.1:3100/ready >/dev/null
echo "广场完攀体验数据已导入，API 存活与数据库就绪检查均通过。"

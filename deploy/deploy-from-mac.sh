#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "用法: bash deploy/deploy-from-mac.sh <SSH地址> <服务器目录>"
  echo "示例: bash deploy/deploy-from-mac.sh root@1.2.3.4 /opt/wanpan-diary"
  exit 1
fi

SSH_TARGET="$1"
REMOTE_DIR="$2"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$ROOT_DIR/.env.production" ]]; then
  echo "缺少 $ROOT_DIR/.env.production，请先复制 .env.production.example 并填写。"
  exit 1
fi

ssh "$SSH_TARGET" "mkdir -p '$REMOTE_DIR'"
rsync -az --delete \
  --exclude .git \
  --exclude node_modules \
  --exclude server/node_modules \
  --exclude server/.env \
  --exclude server/dist \
  --exclude uploads \
  --exclude output \
  --exclude tmp \
  "$ROOT_DIR/" "$SSH_TARGET:$REMOTE_DIR/"

ssh "$SSH_TARGET" "cd '$REMOTE_DIR' && chmod 600 .env.production && docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build"
ssh "$SSH_TARGET" "cd '$REMOTE_DIR' && docker compose --env-file .env.production -f docker-compose.prod.yml ps"

echo "部署命令已完成。等待 HTTPS 证书签发后访问: https://$(awk -F= '/^DOMAIN=/{print $2}' "$ROOT_DIR/.env.production")/health"


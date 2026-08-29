#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 2 ]]; then
  echo "用法: bash deploy/deploy-from-mac.sh [SSH地址] [服务器目录]" >&2
  exit 1
fi

SSH_TARGET="${1:-root@你的服务器IP}"
REMOTE_DIR="${2:-/www/wwwroot/wanpan-diary}"
if [[ "$SSH_TARGET" == *"你的服务器IP"* ]]; then
  echo "请传入 SSH 地址，例如：bash deploy/deploy-from-mac.sh root@1.2.3.4" >&2
  exit 1
fi

# 生产密钥只留在服务器。本脚本不再 rsync 本地目录或 .env.production，
# 只触发服务器端的备份、Git fast-forward、构建、migration 和健康检查。
ssh -t "$SSH_TARGET" "cd '$REMOTE_DIR' && bash deploy/server-deploy.sh"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
if [[ "$EUID" != 0 ]] || ! command -v systemctl >/dev/null; then
  echo "请在现有 Linux 服务器上以 root 执行此安装脚本。" >&2
  exit 1
fi
if [[ ! "$ROOT_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]]; then
  echo "错误：服务器项目目录必须是不含空格的绝对路径。" >&2
  exit 1
fi
cd "$ROOT_DIR"
for command in git curl flock docker timeout; do
  command -v "$command" >/dev/null
done
test -f deploy/auto-deploy.sh
test -s .deploy/current-image-tag
test "$(git symbolic-ref --quiet --short HEAD)" = main
git diff --quiet
git diff --cached --quiet
bash deploy/check-production-env.sh .env.production
docker info >/dev/null

echo "验证服务器现有 GitHub 连接能够在后台使用……"
env -u SSH_AUTH_SOCK GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20' \
  timeout 60s git ls-remote --exit-code origin refs/heads/main >/dev/null </dev/null

cat > /etc/systemd/system/wanpan-auto-deploy.service <<EOF
[Unit]
Description=Deploy tested Wanpan server releases from GitHub
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=$ROOT_DIR
Environment=WANPAN_ROOT=$ROOT_DIR
ExecStart=/bin/bash $ROOT_DIR/deploy/auto-deploy.sh
TimeoutStartSec=0
UMask=0077
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/wanpan-auto-deploy.timer <<'EOF'
[Unit]
Description=Check for a tested Wanpan server release every twelve hours

[Timer]
OnBootSec=12h
OnUnitInactiveSec=12h
AccuracySec=5s
Unit=wanpan-auto-deploy.service

[Install]
WantedBy=timers.target
EOF

chmod 644 /etc/systemd/system/wanpan-auto-deploy.{service,timer}
systemctl daemon-reload
systemctl enable wanpan-auto-deploy.timer
systemctl restart wanpan-auto-deploy.timer
systemctl start --no-block wanpan-auto-deploy.service
echo "已启用：每 12 小时检查 GitHub；只有测试、镜像发布完成的新版本才会部署。"
echo "查看日志：journalctl -u wanpan-auto-deploy.service -n 80 --no-pager"

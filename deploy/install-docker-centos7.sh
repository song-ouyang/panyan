#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 执行此脚本。" >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  systemctl enable --now docker
  echo "Docker 与 Compose 已安装。"
  docker --version
  docker compose version
  exit 0
fi

if [[ ! -r /etc/os-release ]]; then
  echo "无法识别系统版本。" >&2
  exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != "centos" || "${VERSION_ID%%.*}" != "7" ]]; then
  echo "此脚本仅用于 CentOS 7；当前为 ${PRETTY_NAME:-未知系统}。" >&2
  exit 1
fi

echo "注意：CentOS 7 已停止维护。这里仅完成现有服务器部署，建议后续迁移到 Alibaba Cloud Linux 3 或 Rocky Linux 9。"
yum install -y yum-utils ca-certificates curl git
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
# Docker 官方已不再支持 CentOS 7，因此不能安装仓库中面向新系统的 latest。
# 固定到官方仓库最后一组 el7 构建，保证这台遗留服务器可重复安装。
yum install -y \
  docker-ce-26.1.4-1.el7 \
  docker-ce-cli-26.1.4-1.el7 \
  containerd.io-1.6.33-3.1.el7 \
  docker-buildx-plugin-0.14.1-1.el7 \
  docker-compose-plugin-2.27.1-1.el7
systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64|aarch64) ;;
    *) echo "不支持的 CPU 架构：$arch" >&2; exit 1 ;;
  esac
  install -d -m 0755 /usr/local/lib/docker/cli-plugins
  curl -fL "https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-$arch" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
fi

docker --version
docker compose version
docker run --rm hello-world >/dev/null
echo "Docker 安装并启动完成。"

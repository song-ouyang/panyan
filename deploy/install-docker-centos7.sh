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

# CentOS 7 的公共 mirrorlist 已下线。阿里云旧镜像通常已经切到
# Vault；若当前 yum 源失效，仅对本脚本后续命令使用阿里云 Vault，
# 不删除服务器原有 repo 文件。
YUM_BASE_ARGS=()
if ! yum -q makecache >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)
      vault_root="centos-vault"
      vault_gpg_key="RPM-GPG-KEY-CentOS-7"
      ;;
    aarch64)
      vault_root="centos-altarch"
      vault_gpg_key="RPM-GPG-KEY-CentOS-7-aarch64"
      ;;
    *) echo "不支持的 CPU 架构：$(uname -m)" >&2; exit 1 ;;
  esac
  cat > /etc/yum.repos.d/wanpan-centos-vault.repo <<EOF
[wanpan-base]
name=Wanpan CentOS 7 Base Vault
baseurl=https://mirrors.aliyun.com/${vault_root}/7.9.2009/os/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${vault_gpg_key}
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[wanpan-updates]
name=Wanpan CentOS 7 Updates Vault
baseurl=https://mirrors.aliyun.com/${vault_root}/7.9.2009/updates/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${vault_gpg_key}
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[wanpan-extras]
name=Wanpan CentOS 7 Extras Vault
baseurl=https://mirrors.aliyun.com/${vault_root}/7.9.2009/extras/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${vault_gpg_key}
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
  YUM_BASE_ARGS=(--disablerepo=* --enablerepo=wanpan-base,wanpan-updates,wanpan-extras)
fi

yum "${YUM_BASE_ARGS[@]}" install -y yum-utils ca-certificates curl git
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
# Docker 官方已不再支持 CentOS 7，因此不能安装仓库中面向新系统的 latest。
# 固定到官方仓库最后一组 el7 构建，保证这台遗留服务器可重复安装。
docker_packages=(
  docker-ce-26.1.4-1.el7
  docker-ce-cli-26.1.4-1.el7
  containerd.io-1.6.33-3.1.el7
  docker-buildx-plugin-0.14.1-1.el7
  docker-compose-plugin-2.27.1-1.el7
)
docker_installed=0
for attempt in 1 2 3; do
  if yum "${YUM_BASE_ARGS[@]}" --enablerepo=docker-ce-stable \
    --setopt=docker-ce-stable.timeout=60 \
    --setopt=docker-ce-stable.retries=5 \
    install -y "${docker_packages[@]}"; then
    docker_installed=1
    break
  fi
  echo "Docker 软件源连接失败（第 ${attempt}/3 次），清理缓存后重试……" >&2
  yum "${YUM_BASE_ARGS[@]}" --enablerepo=docker-ce-stable clean metadata >/dev/null 2>&1 || true
  sleep 3
done
if [[ "$docker_installed" != "1" ]]; then
  echo "Docker 安装失败。请检查服务器能否访问 mirrors.aliyun.com 后重新执行本脚本。" >&2
  exit 1
fi
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
docker info >/dev/null
echo "Docker 安装并启动完成。"

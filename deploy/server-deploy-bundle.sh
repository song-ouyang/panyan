#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
REMOTE="${WANPAN_REMOTE:-origin}"
BRANCH="${WANPAN_BRANCH:-main}"
REPOSITORY="${WANPAN_BUNDLE_REPOSITORY:-song-ouyang/panyan}"

cd "$ROOT_DIR"

if ! docker info >/dev/null 2>&1; then
  echo "错误：Docker 服务未运行。" >&2
  exit 1
fi
if [[ ! -d .git ]]; then
  echo "错误：$ROOT_DIR 不是 Git 仓库。" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误：服务器存在未提交的 tracked 文件改动，已停止部署。" >&2
  git status --short >&2
  exit 1
fi

echo "拉取 $REMOTE/$BRANCH……"
git fetch --prune "$REMOTE" "$BRANCH"
current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "错误：当前分支是 ${current_branch:-detached HEAD}，请先切换到 $BRANCH。" >&2
  exit 1
fi

REVISION="$(git rev-parse FETCH_HEAD)"
SHORT_REVISION="${REVISION:0:12}"
BUNDLE_TAG="${1:-${WANPAN_BUNDLE_TAG:-server-bundle-$SHORT_REVISION}}"
BASE_URL="https://github.com/$REPOSITORY/releases/download/$BUNDLE_TAG"
TMP_DIR="$(mktemp -d /tmp/wanpan-server-bundle.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

download() {
  local file="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if curl --fail --location --silent --show-error \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout 20 --max-time 1200 \
      "$BASE_URL/$file" -o "$TMP_DIR/$file"; then
      return 0
    fi
    echo "下载 $file 失败（第 $attempt/5 次），稍后重试……" >&2
    sleep $((attempt * 3))
  done
  return 1
}

echo "下载 GitHub Release 预构建镜像包 $BUNDLE_TAG……"
download REVISION
download SHA256SUMS
download wanpan-diary-api-amd64.tar.gz
download postgres-16-alpine-amd64.tar.gz

bundle_revision="$(tr -d '\r\n' < "$TMP_DIR/REVISION")"
if [[ "$bundle_revision" != "$REVISION" ]]; then
  echo "错误：镜像包对应 Git $bundle_revision，但服务器当前为 $REVISION。" >&2
  exit 1
fi

(
  cd "$TMP_DIR"
  sha256sum --check SHA256SUMS
)

echo "加载 PostgreSQL 与 API 镜像……"
gzip -dc "$TMP_DIR/postgres-16-alpine-amd64.tar.gz" | docker load
gzip -dc "$TMP_DIR/wanpan-diary-api-amd64.tar.gz" | docker load

docker image inspect postgres:16-alpine >/dev/null
docker image inspect "wanpan-diary-api:$SHORT_REVISION" >/dev/null

api_arch="$(docker image inspect --format '{{.Architecture}}' "wanpan-diary-api:$SHORT_REVISION")"
postgres_arch="$(docker image inspect --format '{{.Architecture}}' postgres:16-alpine)"
api_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "wanpan-diary-api:$SHORT_REVISION")"
if [[ "$api_arch" != "amd64" || "$postgres_arch" != "amd64" ]]; then
  echo "错误：镜像架构不匹配（API=$api_arch，PostgreSQL=$postgres_arch）。" >&2
  exit 1
fi
if [[ "$api_revision" != "$REVISION" ]]; then
  echo "错误：API 镜像标签中的 Git 提交号不匹配。" >&2
  exit 1
fi

WANPAN_SKIP_BUILD=1 \
WANPAN_EXPECT_REVISION="$REVISION" \
  bash deploy/server-deploy.sh

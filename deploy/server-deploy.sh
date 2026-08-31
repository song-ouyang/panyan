#!/usr/bin/env bash
set -Eeuo pipefail

# 防止 git pull 更新正在执行的脚本：先把完整脚本送入新的 Bash 进程。
if [[ "${WANPAN_DEPLOY_BOOTSTRAPPED:-0}" != "1" ]]; then
  export WANPAN_DEPLOY_BOOTSTRAPPED=1
  exec bash -s -- "$@" < "$0"
fi

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
ENV_FILE="${WANPAN_ENV_FILE:-.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"
BRANCH="${WANPAN_BRANCH:-main}"
REMOTE="${WANPAN_REMOTE:-origin}"
WAIT_SECONDS="${WANPAN_WAIT_SECONDS:-180}"
SKIP_BUILD="${WANPAN_SKIP_BUILD:-0}"
EXPECTED_REVISION="${WANPAN_EXPECT_REVISION:-}"

cd "$ROOT_DIR"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "错误：未安装 Docker Compose。CentOS 7 可先运行 bash deploy/install-docker-centos7.sh" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "错误：Docker 服务未运行，请执行 systemctl enable --now docker" >&2
  exit 1
fi
if [[ ! -d .git ]]; then
  echo "错误：$ROOT_DIR 不是 Git 仓库。" >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误：缺少 $ROOT_DIR/$ENV_FILE。" >&2
  exit 1
fi
chmod 600 "$ENV_FILE"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误：服务器存在未提交的 tracked 文件改动，为避免覆盖已停止部署。" >&2
  git status --short >&2
  exit 1
fi

OLD_REV="$(git rev-parse HEAD)"
OLD_TAG="$(cat .deploy/current-image-tag 2>/dev/null || true)"

postgres_id="$("${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)"
if [[ -n "$postgres_id" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "$postgres_id" 2>/dev/null || true)" == "true" ]]; then
  echo "部署前备份数据库……"
  WANPAN_ENV_FILE="$ENV_FILE" bash deploy/backup.sh "$COMPOSE_FILE"
fi

echo "拉取 $REMOTE/$BRANCH……"
git fetch --prune "$REMOTE" "$BRANCH"
TARGET_REV="$(git rev-parse "$REMOTE/$BRANCH")"
if [[ -n "$EXPECTED_REVISION" && "$TARGET_REV" != "$EXPECTED_REVISION" ]]; then
  echo "错误：预构建镜像对应 Git $EXPECTED_REVISION，但远端 $REMOTE/$BRANCH 已更新为 $TARGET_REV。" >&2
  exit 1
fi
current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "错误：当前分支是 ${current_branch:-detached HEAD}，请先切换到 $BRANCH。" >&2
  exit 1
fi
git merge --ff-only "$REMOTE/$BRANCH"
NEW_REV="$(git rev-parse HEAD)"
NEW_TAG="${NEW_REV:0:12}"

if [[ -n "$EXPECTED_REVISION" && "$NEW_REV" != "$EXPECTED_REVISION" ]]; then
  echo "错误：预构建镜像对应 Git $EXPECTED_REVISION，但服务器当前为 $NEW_REV。" >&2
  exit 1
fi

bash deploy/check-production-env.sh "$ENV_FILE"
export API_IMAGE_TAG="$NEW_TAG"
"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet

if [[ "$SKIP_BUILD" == "1" ]]; then
  if ! docker image inspect "wanpan-diary-api:$NEW_TAG" >/dev/null 2>&1; then
    echo "错误：本机缺少预构建镜像 wanpan-diary-api:$NEW_TAG。" >&2
    exit 1
  fi
  if ! docker image inspect postgres:16-alpine >/dev/null 2>&1; then
    echo "错误：本机缺少预构建镜像 postgres:16-alpine。" >&2
    exit 1
  fi
  echo "使用已校验的预构建 API 镜像 $NEW_TAG。"
else
  echo "构建 API 镜像 $NEW_TAG……"
  build_args=(build)
  if [[ "${WANPAN_PULL_BASE:-0}" == "1" ]]; then
    build_args+=(--pull)
  fi
  "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "${build_args[@]}" api
fi
echo "启动 PostgreSQL 与 API（启动时自动执行幂等 migration）……"
up_args=(up -d --remove-orphans)
if [[ "$SKIP_BUILD" == "1" ]]; then
  up_args+=(--no-build)
fi
"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "${up_args[@]}"

api_id="$("${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q api)"
deadline=$((SECONDS + WAIT_SECONDS))
status=""
while (( SECONDS < deadline )); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$api_id" 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  [[ "$status" == "unhealthy" || "$status" == "exited" || "$status" == "dead" ]] && break
  sleep 2
done

if [[ "$status" != "healthy" ]]; then
  echo "错误：新 API 未就绪（状态：${status:-unknown}）。最近日志如下：" >&2
  "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs --tail=120 api postgres >&2 || true
  if [[ -n "$OLD_TAG" ]] && docker image inspect "wanpan-diary-api:$OLD_TAG" >/dev/null 2>&1; then
    echo "自动恢复上一 API 镜像 $OLD_TAG……" >&2
    API_IMAGE_TAG="$OLD_TAG" "${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build || true
  fi
  exit 1
fi

mkdir -p .deploy
chmod 700 .deploy
if [[ -n "$OLD_TAG" && "$OLD_TAG" != "$NEW_TAG" ]]; then
  printf '%s\n' "$OLD_TAG" > .deploy/previous-image-tag
fi
printf '%s\n' "$NEW_TAG" > .deploy/current-image-tag
printf '%s\n' "$OLD_REV" > .deploy/previous-git-revision
chmod 600 .deploy/*

host_port="$(docker inspect -f '{{with (index .NetworkSettings.Ports "3000/tcp")}}{{(index . 0).HostPort}}{{end}}' "$api_id" 2>/dev/null || true)"
if [[ -n "$host_port" ]]; then
  curl --fail --silent --show-error "http://127.0.0.1:$host_port/ready" >/dev/null
fi
"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
echo "部署成功：Git ${NEW_REV:0:12}，API/数据库就绪。"

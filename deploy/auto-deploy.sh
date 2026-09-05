#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${WANPAN_AUTO_BOOTSTRAPPED:-0}" != 1 ]]; then
  export WANPAN_AUTO_BOOTSTRAPPED=1
  exec bash -s -- "$@" < "$0"
fi

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
REMOTE="${WANPAN_REMOTE:-origin}"
BRANCH="${WANPAN_BRANCH:-main}"
cd "$ROOT_DIR"
source deploy/deploy-common.sh
# Another deployment/rollback owns the lock; the timer will check again.
wanpan_lock_deployment || exit 0

if [[ "$(git symbolic-ref --quiet --short HEAD || true)" != "$BRANCH" ]]; then
  echo "错误：自动部署要求服务器位于 $BRANCH 分支。" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误：服务器有未提交的 tracked 改动，已停止自动部署。" >&2
  exit 1
fi

# Reuse the server's existing GitHub authentication, with no interactive
# password prompts or automatic acceptance of an unknown SSH host key.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20'
# CentOS 7 Git 1.8 requires a whole path component for wildcard refspecs.
# Mirror remote tags in a private namespace: pruning must not delete local
# tags, and a deleted remote ready marker must stop authorizing deployment.
timeout 120s git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 \
  fetch --quiet --no-tags --prune "$REMOTE" \
  "refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" \
  '+refs/tags/*:refs/wanpan-auto-deploy/tags/*' 9>&- </dev/null
# Only this shell owns the lock during fetch. Timeout/git maintenance children
# must not retain it after the poll exits or consume the bootstrap script stdin.
branch_head="$(git rev-parse "refs/remotes/$REMOTE/$BRANCH")"
revision="$(wanpan_ready_revision "$branch_head")"
[[ -n "$revision" ]] || exit 0

current="$(cat .deploy/current-image-tag 2>/dev/null || true)"
failed="$(cat .deploy/auto-deploy-failed-revision 2>/dev/null || true)"
[[ "$failed" != "$revision" ]] || exit 0
success="$(cat .deploy/auto-deploy-success-revision 2>/dev/null || true)"
if [[ "$current" == "${revision:0:12}" && "$success" == "$revision" ]]; then
  exit 0
fi

# Refuse stale or divergent code before downloading images or backing up.
if [[ "$current" != "${revision:0:12}" ]]; then
  WANPAN_EXPECT_REVISION="$revision" WANPAN_ALLOW_ANCESTOR_REVISION=1 \
    wanpan_select_revision "$branch_head" >/dev/null
fi

# Persist the attempt before starting. A failed/interrupted deployment is
# retried only for a newer ready revision or after an operator clears it.
printf '%s\n' "$revision" > .deploy/auto-deploy-failed-revision
chmod 600 .deploy/auto-deploy-failed-revision
if [[ "$current" != "${revision:0:12}" ]]; then
  echo "发现测试和镜像构建均已完成的新版本 ${revision:0:12}，开始自动部署。"
  WANPAN_EXPECT_REVISION="$revision" WANPAN_ALLOW_ANCESTOR_REVISION=1 \
    bash deploy/server-deploy-bundle.sh "server-bundle-${revision:0:12}" </dev/null
fi

for endpoint in health ready; do
  curl --fail --silent --show-error --output /dev/null \
    --connect-timeout 10 --max-time 20 --retry 5 --retry-delay 5 \
    "https://panyan-api.gblh.cloud/$endpoint"
done
printf '%s\n' "$revision" > .deploy/auto-deploy-success-revision
chmod 600 .deploy/auto-deploy-success-revision
rm -f .deploy/auto-deploy-failed-revision
echo "自动部署完成：${revision:0:12}，本机和公网服务/数据库检查通过。"

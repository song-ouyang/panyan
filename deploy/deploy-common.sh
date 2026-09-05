#!/usr/bin/env bash

# Source after entering WANPAN_ROOT. The bundle and inner deployment inherit
# the same descriptor, so manual and CI deployments cannot overlap either.
wanpan_lock_deployment() {
  if [[ "${WANPAN_DEPLOY_LOCKED:-0}" == 1 ]]; then
    return
  fi
  mkdir -p .deploy
  chmod 700 .deploy
  exec 9>.deploy/deploy.lock
  if ! flock -n 9; then
    echo "错误：已有部署或回滚正在运行，请等待它完成后重试。" >&2
    return 1
  fi
  export WANPAN_DEPLOY_LOCKED=1
}

# Manual deployment follows the branch head. CI may pin an earlier main
# commit: a later client-only push must not invalidate a tested API bundle.
# The pinned commit must belong to main and must fast-forward this checkout.
wanpan_select_revision() {
  local fetched="$1"
  local expected="${WANPAN_EXPECT_REVISION:-}"
  local target="$fetched"
  if [[ -n "$expected" ]]; then
    if [[ ! "$expected" =~ ^[0-9a-f]{40}$ ]]; then
      echo "错误：WANPAN_EXPECT_REVISION 必须是完整的 Git 提交号。" >&2
      return 1
    fi
    if [[ "${WANPAN_ALLOW_ANCESTOR_REVISION:-0}" == 1 ]]; then
      if ! git merge-base --is-ancestor "$expected" "$fetched"; then
        echo "错误：指定镜像提交不属于当前远端分支的历史。" >&2
        return 1
      fi
    elif [[ "$expected" != "$fetched" ]]; then
      echo "错误：预构建镜像提交与远端分支最新提交不一致。" >&2
      return 1
    fi
    target="$expected"
  fi
  if ! git merge-base --is-ancestor HEAD "$target"; then
    echo "错误：指定提交落后于服务器代码或已分叉，拒绝覆盖或倒退部署。" >&2
    return 1
  fi
  printf '%s\n' "$target"
}

# A ready tag is written only after CI tests and all release uploads succeed.
# Walk main's first-parent history, so merge commits and client-only follow-up
# pushes work without relying on tag timestamps or a moving latest release.
wanpan_ready_revision() {
  local branch_head="$1" revision tag tagged
  while IFS= read -r revision; do
    tag="refs/tags/server-ready-${revision:0:12}"
    tagged="$(git rev-parse --verify "$tag^{commit}" 2>/dev/null || true)"
    [[ "$tagged" == "$revision" ]] || continue
    if git diff --quiet "$revision" "$branch_head" -- \
      server data/gyms.public-verified.json package.json package-lock.json \
      .dockerignore .env.production.example docker-compose.server.yml \
      docker-compose.prod.yml deploy .github/workflows/server-image-bundle.yml; then
      printf '%s\n' "$revision"
    fi
    # If backend inputs changed after the latest ready revision, wait for CI.
    return 0
  done < <(git rev-list --first-parent "$branch_head")
}

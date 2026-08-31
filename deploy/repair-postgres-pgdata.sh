#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
ENV_FILE="${WANPAN_ENV_FILE:-.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"

cd "$ROOT_DIR"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "错误：未安装 Docker Compose。" >&2
  exit 1
fi

[[ -f "$ENV_FILE" ]] || { echo "错误：缺少 $ENV_FILE。" >&2; exit 1; }

postgres_id="$("${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -aq postgres 2>/dev/null || true)"
[[ -n "$postgres_id" ]] || { echo "错误：未找到 PostgreSQL 容器。" >&2; exit 1; }

health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$postgres_id" 2>/dev/null || true)"
restarts="$(docker inspect -f '{{.RestartCount}}' "$postgres_id" 2>/dev/null || printf '0')"
if [[ "$health" != "starting" && "$health" != "unhealthy" ]]; then
  echo "错误：PostgreSQL 健康状态为 ${health:-未配置}，不符合可自动修复的首次初始化故障。" >&2
  exit 1
fi
if [[ "$health" == "starting" ]] && (( restarts < 2 )); then
  echo "错误：PostgreSQL 仍在首次启动窗口，尚不能判定为循环初始化故障。" >&2
  exit 1
fi
if (( restarts < 1 )); then
  echo "错误：PostgreSQL 尚无重启记录，不允许归档数据卷。" >&2
  exit 1
fi

actual_pgdata="$(
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$postgres_id" \
    | sed -n 's/^PGDATA=//p' | tail -n 1
)"
if [[ "$actual_pgdata" != "/var/lib/postgresql/data" ]]; then
  echo "错误：失败容器实际使用 PGDATA=${actual_pgdata:-未设置}，不是本脚本支持的卷根目录布局。" >&2
  exit 1
fi

configured_pgdata="$(grep -E '^POSTGRES_PGDATA=' "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '\r' || true)"
configured_pgdata="${configured_pgdata%\"}"
configured_pgdata="${configured_pgdata#\"}"
configured_pgdata="${configured_pgdata%\'}"
configured_pgdata="${configured_pgdata#\'}"
case "$configured_pgdata" in
  ""|/var/lib/postgresql/data|/var/lib/postgresql/data/pgdata) ;;
  *)
    echo "错误：POSTGRES_PGDATA 使用了自定义目录 $configured_pgdata，不允许自动归档。" >&2
    exit 1
    ;;
esac

logs="$(docker logs --tail=500 "$postgres_id" 2>&1 || true)"
if [[ "$logs" != *'could not write to file "postmaster.pid": Operation not permitted'* ]] ||
   [[ "$logs" != *'pg_wal/xlogtemp'* ]] ||
   [[ "$logs" != *'initdb: removing contents of data directory'* ]]; then
  echo "错误：日志不符合已知的 CentOS 7 卷根目录初始化失败，未做任何数据变更。" >&2
  docker logs --tail=80 "$postgres_id" >&2 || true
  exit 1
fi
if [[ "$logs" == *'database system is ready to accept connections'* ]]; then
  echo "错误：日志曾显示数据库成功就绪，不能当作首次失败卷自动归档。" >&2
  exit 1
fi

volume="$(
  docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' \
    "$postgres_id"
)"
[[ -n "$volume" ]] || { echo "错误：未找到 PostgreSQL 命名卷。" >&2; exit 1; }
volume_driver="$(docker volume inspect -f '{{.Driver}}' "$volume")"
[[ "$volume_driver" == "local" ]] || { echo "错误：数据卷驱动为 $volume_driver，脚本只支持 local 命名卷。" >&2; exit 1; }
mountpoint="$(docker volume inspect -f '{{.Mountpoint}}' "$volume")"
[[ -d "$mountpoint" ]] || { echo "错误：卷挂载点不存在。" >&2; exit 1; }

echo "停止失败的 API/PostgreSQL 容器（保留容器与命名卷）……"
"${COMPOSE[@]}" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" stop api postgres
if [[ "$(docker inspect -f '{{.State.Running}}' "$postgres_id" 2>/dev/null || true)" != "false" ]]; then
  echo "错误：PostgreSQL 容器未完全停止，未触碰数据卷。" >&2
  exit 1
fi

if [[ -s "$mountpoint/pgdata/PG_VERSION" ]]; then
  echo "错误：pgdata 子目录已有数据库标记，未做任何数据变更。" >&2
  exit 1
fi
if [[ -s "$mountpoint/global/pg_control" ]]; then
  echo "错误：卷根目录存在 PostgreSQL 控制文件，可能是有效数据库，未做任何数据变更。" >&2
  exit 1
fi

archive_name="failed-root-init-$(date +%Y%m%d-%H%M%S)"
archive_dir="$mountpoint/$archive_name"
mkdir -m 700 "$archive_dir"

shopt -s dotglob nullglob
moved=0
for item in "$mountpoint"/*; do
  [[ "$item" == "$archive_dir" ]] && continue
  mv -- "$item" "$archive_dir/"
  moved=1
done
shopt -u dotglob nullglob

if [[ "$moved" == 0 ]]; then
  rmdir "$archive_dir"
  echo "失败的卷根目录已是空的，无需归档。"
else
  echo "已将失败的半初始化文件保留在命名卷的 $archive_name 目录。"
fi

if grep -q '^POSTGRES_PGDATA=' "$ENV_FILE"; then
  sed -i 's|^POSTGRES_PGDATA=.*|POSTGRES_PGDATA=/var/lib/postgresql/data/pgdata|' "$ENV_FILE"
else
  printf '\nPOSTGRES_PGDATA=/var/lib/postgresql/data/pgdata\n' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

echo "修复准备完成：生产卷 $volume 未删除，新数据库将在 pgdata 子目录初始化。"

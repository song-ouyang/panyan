#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${WANPAN_ROOT:-/www/wwwroot/wanpan-diary}"
ENV_FILE="${WANPAN_ENV_FILE:-$ROOT_DIR/.env.production}"
COMPOSE_FILE="${WANPAN_COMPOSE_FILE:-docker-compose.server.yml}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误：找不到 $ENV_FILE" >&2
  exit 1
fi

read -r -p "请输入 App Review 专用手机号（中国大陆 11 位）：" review_phone
read -r -s -p "请输入 App Review 专用 6 位验证码：" review_code
echo

if [[ ! "$review_phone" =~ ^1[0-9]{10}$ ]]; then
  echo "错误：手机号格式不正确。" >&2
  exit 1
fi
if [[ ! "$review_code" =~ ^[0-9]{6}$ ]]; then
  echo "错误：验证码必须是 6 位数字。" >&2
  exit 1
fi

backup_dir="$ROOT_DIR/backups/config"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
backup_file="$backup_dir/env-production-$(date +%Y%m%d-%H%M%S).backup"
install -m 600 "$ENV_FILE" "$backup_file"

next_env="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
REVIEW_PHONE="$review_phone" REVIEW_CODE="$review_code" awk '
  BEGIN { phoneFound=0; codeFound=0 }
  index($0, "APP_REVIEW_LOGIN_PHONE=") == 1 {
    print "APP_REVIEW_LOGIN_PHONE=" ENVIRON["REVIEW_PHONE"]
    phoneFound=1
    next
  }
  index($0, "APP_REVIEW_LOGIN_CODE=") == 1 {
    print "APP_REVIEW_LOGIN_CODE=" ENVIRON["REVIEW_CODE"]
    codeFound=1
    next
  }
  { print }
  END {
    if (!phoneFound) print "APP_REVIEW_LOGIN_PHONE=" ENVIRON["REVIEW_PHONE"]
    if (!codeFound) print "APP_REVIEW_LOGIN_CODE=" ENVIRON["REVIEW_CODE"]
  }
' "$ENV_FILE" > "$next_env"
chmod 600 "$next_env"
mv "$next_env" "$ENV_FILE"

cd "$ROOT_DIR"
bash deploy/check-production-env.sh "$ENV_FILE"
image_tag="${API_IMAGE_TAG:-$(cat .deploy/current-image-tag 2>/dev/null || true)}"
if [[ -z "$image_tag" ]]; then
  echo "错误：找不到当前 API 镜像版本，请先完成一次生产部署。" >&2
  exit 1
fi
if ! docker image inspect "wanpan-diary-api:$image_tag" >/dev/null 2>&1; then
  echo "错误：本机不存在审核配置要重启的 API 镜像 wanpan-diary-api:$image_tag。" >&2
  exit 1
fi
API_IMAGE_TAG="$image_tag" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
  up -d --no-build --no-deps --force-recreate api

for _ in $(seq 1 30); do
  if curl -fsS --max-time 5 http://127.0.0.1:3100/ready >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS --max-time 5 http://127.0.0.1:3100/ready >/dev/null

send_status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
  -H 'content-type: application/json' \
  -d "{\"phone\":\"$review_phone\"}" \
  http://127.0.0.1:3100/api/auth/sms/send)"
login_status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
  -H 'content-type: application/json' \
  -d "{\"phone\":\"$review_phone\",\"code\":\"$review_code\"}" \
  http://127.0.0.1:3100/api/auth/sms/login)"

if [[ "$send_status" != "200" || "$login_status" != "200" ]]; then
  echo "错误：审核账号烟雾测试失败（send=$send_status, login=$login_status）。" >&2
  echo "生产配置备份位于：$backup_file" >&2
  exit 1
fi

echo "App Review 审核账号已配置，发送与登录接口均验证通过。"
echo "生产配置备份位于：$backup_file"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
ENV_FILE="${1:-${WANPAN_ENV_FILE:-.env.production}}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误：缺少 $ROOT_DIR/$ENV_FILE，请先由 .env.production.example 创建。" >&2
  exit 1
fi

env_value() {
  local key="$1"
  awk -v key="$key" '
    $0 !~ /^[[:space:]]*#/ && index($0, key "=") == 1 {
      value=substr($0, length(key)+2)
      sub(/\r$/, "", value)
      if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) value=substr(value, 2, length(value)-2)
      print value
      exit
    }
  ' "$ENV_FILE"
}

errors=0
warnings=0
fail() { echo "错误：$*" >&2; errors=$((errors + 1)); }
warn() { echo "警告：$*" >&2; warnings=$((warnings + 1)); }

required=(DOMAIN POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD JWT_SECRET WECHAT_APP_ID WECHAT_APP_SECRET UPLOAD_MODE)
for key in "${required[@]}"; do
  value="$(env_value "$key")"
  if [[ -z "$value" ]] || [[ "$value" =~ 请|填写|替换|replace|example ]]; then
    fail "$key 未填写或仍是示例值"
  fi
done

domain="$(env_value DOMAIN)"
if [[ -n "$domain" ]] && [[ "$domain" == *://* || "$domain" == */* || "$domain" =~ [[:space:]] ]]; then
  fail "DOMAIN 只能填写主机名，不能带协议、路径或空格"
fi

jwt_secret="$(env_value JWT_SECRET)"
db_password="$(env_value POSTGRES_PASSWORD)"
(( ${#jwt_secret} >= 32 )) || fail "JWT_SECRET 至少需要 32 个字符"
(( ${#db_password} >= 12 )) || fail "POSTGRES_PASSWORD 至少需要 12 个字符"

upload_mode="$(env_value UPLOAD_MODE)"
if [[ "$upload_mode" == "oss" ]]; then
  for key in OSS_REGION OSS_BUCKET OSS_ACCESS_KEY_ID OSS_ACCESS_KEY_SECRET OSS_PUBLIC_BASE_URL; do
    value="$(env_value "$key")"
    if [[ -z "$value" ]] || [[ "$value" =~ 请|填写|替换|replace|example ]]; then
      fail "UPLOAD_MODE=oss 时 $key 必须填写"
    fi
  done
  oss_base="$(env_value OSS_PUBLIC_BASE_URL)"
  [[ "$oss_base" == https://* ]] || fail "OSS_PUBLIC_BASE_URL 必须是 HTTPS 地址"
elif [[ "$upload_mode" != "local" ]]; then
  fail "UPLOAD_MODE 只能是 local 或 oss"
fi

allow_gym_import="$(env_value ALLOW_PRODUCTION_GYM_IMPORT)"
if [[ -n "$allow_gym_import" && "$allow_gym_import" != "false" ]]; then
  fail "ALLOW_PRODUCTION_GYM_IMPORT 不能长期写入生产配置；只能在备份后为单次目录导入命令临时传入 true"
fi

apple_client="$(env_value APPLE_CLIENT_ID)"
apple_team="$(env_value APPLE_TEAM_ID)"
if [[ -z "$apple_client" || -z "$apple_team" || "$apple_client" =~ 请|填写 || "$apple_team" =~ 请|填写 ]]; then
  warn "Apple Client ID/Team ID 尚未完整配置，Apple 登录或 AASA 将不可用"
fi

review_phone="$(env_value APP_REVIEW_LOGIN_PHONE)"
review_code="$(env_value APP_REVIEW_LOGIN_CODE)"
review_ready=0
if [[ -n "$review_phone" || -n "$review_code" ]]; then
  if [[ ! "$review_phone" =~ ^1[0-9]{10}$ ]]; then
    fail "APP_REVIEW_LOGIN_PHONE 必须是中国大陆 11 位手机号"
  elif [[ ! "$review_code" =~ ^[0-9]{6}$ ]]; then
    fail "APP_REVIEW_LOGIN_CODE 必须是 6 位数字"
  elif [[ "$review_code" == "246810" ]]; then
    fail "APP_REVIEW_LOGIN_CODE 仍是仓库曾使用的公开示例值，请立即轮换"
  else
    review_ready=1
  fi
else
  warn "未配置 App Store 审核固定账号，提交审核前需补充"
fi

aliyun_keys=(ALIYUN_ACCESS_KEY_ID ALIYUN_ACCESS_KEY_SECRET ALIYUN_SMS_SIGN_NAME ALIYUN_SMS_TEMPLATE_CODE)
aliyun_count=0
for key in "${aliyun_keys[@]}"; do
  value="$(env_value "$key")"
  if [[ -n "$value" && ! "$value" =~ 请|填写|替换|replace|example ]]; then
    aliyun_count=$((aliyun_count + 1))
  fi
done
aliyun_ready=0
if (( aliyun_count == ${#aliyun_keys[@]} )); then
  aliyun_ready=1
elif (( aliyun_count > 0 )); then
  fail "阿里云短信配置不完整，ALIYUN_ACCESS_KEY_ID/SECRET、SIGN_NAME、TEMPLATE_CODE 必须全部填写"
else
  fail "未配置阿里云号码认证服务，正式用户的手机号验证码登录不可用"
fi

# 审核固定账号只用于 App Review，不能代替面向真实用户的
# 短信通道。生产预检因此始终要求 Aliyun 四项配置完整。

mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")"
if [[ "$mode" != "600" ]]; then
  warn "$ENV_FILE 权限为 ${mode}，部署脚本会自动收紧为 600"
fi

if (( errors > 0 )); then
  echo "生产配置检查失败：$errors 个错误，$warnings 个警告。未输出任何密钥值。" >&2
  exit 1
fi

echo "生产配置检查通过（$warnings 个警告，未输出任何密钥值）。"

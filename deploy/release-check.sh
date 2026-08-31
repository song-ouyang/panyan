#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/7] 检查部署脚本与 Git diff……"
bash -n deploy/*.sh
git diff --check

echo "[2/7] 检查、测试并构建后端……"
npm run check
npm test
npm run build

echo "[3/7] 审计生产 Node 依赖……"
npm audit --registry=https://registry.npmjs.org --omit=dev --audit-level=high

echo "[4/7] 检查 Flutter……"
(cd flutter_app && \
  flutter pub get --enforce-lockfile && \
  dart analyze lib test && \
  flutter test && \
  flutter build apk --release && \
  flutter build ios --release --no-codesign)
if rg -q 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' flutter_app/android/app/build.gradle.kts; then
  echo "错误：Android release 不能使用 debug 签名。" >&2
  exit 1
fi
if [[ ! -f flutter_app/android/key.properties ]]; then
  echo "提示：Android 未配置上架 keystore，本次 APK 仅用于未签名构建验证。"
fi
echo "[5/7] 校验两种生产 Compose（使用临时假值，不读取或输出真实密钥）……"
compose_env=(
  API_IMAGE_TAG=release-check
  POSTGRES_PASSWORD=release-check-postgres-password-32
  JWT_SECRET=release-check-jwt-secret-32-characters
  WECHAT_APP_ID=wx-release-check
  WECHAT_APP_SECRET=release-check-secret
  WECHAT_MOBILE_APP_ID=
  WECHAT_MOBILE_APP_SECRET=
  APPLE_CLIENT_ID=com.wanpan.wanpanDiary
  APPLE_TEAM_ID=TESTTEAM01
  DOMAIN=release-check.invalid
  UPLOAD_MODE=local
)
env "${compose_env[@]}" docker compose --env-file .env.production.example -f docker-compose.server.yml config --quiet
env "${compose_env[@]}" docker compose --env-file .env.production.example -f docker-compose.prod.yml config --quiet

echo "[6/7] 构建生产 API 镜像……"
docker build -t wanpan-diary-api:release-check -f server/Dockerfile .

echo "[7/7] 检查生产配置模板会拒绝占位密钥……"
if bash deploy/check-production-env.sh .env.production.example >/dev/null 2>&1; then
  echo "错误：生产配置模板不应直接通过密钥检查。" >&2
  exit 1
fi

echo "发布前检查全部通过。真实 PostgreSQL E2E 需另行使用测试库运行 npm run test:server:e2e。"

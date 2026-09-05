#!/usr/bin/env bash
set -Eeuo pipefail

echo "错误：已停止向生产环境导入广场体验数据，ALLOW_PRODUCTION_SQUARE_SEED=true 也无法启用。仅可在本地开发环境运行 db:seed-square-experience。" >&2
exit 1

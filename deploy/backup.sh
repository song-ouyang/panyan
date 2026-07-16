#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p backups
STAMP="$(date +%Y%m%d-%H%M%S)"
docker compose --env-file .env.production -f docker-compose.prod.yml exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-wanpan}" "${POSTGRES_DB:-wanpan}" | gzip > "backups/wanpan-$STAMP.sql.gz"
find backups -name 'wanpan-*.sql.gz' -mtime +14 -delete
echo "备份完成: backups/wanpan-$STAMP.sql.gz"


# 完攀日记生产部署

当前服务器环境：CentOS 7、项目目录 `/www/wwwroot/wanpan-diary`，并由宝塔/Nginx 承担 HTTPS。CentOS 7 已停止维护，Docker 官方也只支持仍在维护的 CentOS 版本；安装脚本因此固定使用官方仓库最后的 CentOS 7 构建。本方案可用于当前上线，但系统与 Docker 均无法继续获得完整安全更新，应尽快迁移到 Alibaba Cloud Linux 3 或 Rocky Linux 9。

生产 Compose 的 PostgreSQL 不暴露 `5432`，API 只监听服务器本机 `127.0.0.1:3100`；公网只开放 Nginx 的 `80/443`。

## 首次部署

域名需提前将 A 记录指向服务器公网 IP；阿里云安全组放行 TCP `22`、`80`、`443`，不要放行 `3100` 或 `5432`。

在 Mac 推送代码前，可一键复验后端、Flutter、依赖审计、Compose 和生产镜像：

```bash
npm run release:check
```

服务器执行下面这一整段：

```bash
set -euo pipefail
cd /www/wwwroot/wanpan-diary
git pull --ff-only origin main
bash deploy/install-docker-centos7.sh
test -f .env.production || cp .env.production.example .env.production
chmod 600 .env.production
echo "请确认 /www/wwwroot/wanpan-diary/.env.production 已填写，再执行：bash deploy/server-deploy.sh"
```

如果 `.env.production` 还没填写，可使用宝塔文件管理器或 `vi .env.production`，不依赖 `nano`。至少配置：

```env
DOMAIN=panyan-api.gblh.cloud
ACME_EMAIL=你的证书通知邮箱
API_HOST_PORT=3100

POSTGRES_DB=wanpan
POSTGRES_USER=wanpan
POSTGRES_PASSWORD=至少32位随机值
# CentOS 7 兼容配置；新部署保持这个子目录
POSTGRES_PGDATA=/var/lib/postgresql/data/pgdata
JWT_SECRET=另一段至少32位随机值

WECHAT_APP_ID=微信小程序AppID
WECHAT_APP_SECRET=微信小程序AppSecret
# 未申请微信开放平台「移动应用」时保持为空
WECHAT_MOBILE_APP_ID=
WECHAT_MOBILE_APP_SECRET=
APPLE_CLIENT_ID=com.wanpan.wanpanDiary
APPLE_TEAM_ID=Apple开发者TeamID

MODERATION_MODE=manual
UPLOAD_MODE=oss
OSS_REGION=oss-cn-chengdu
OSS_BUCKET=Bucket名称
OSS_ACCESS_KEY_ID=RAM用户AccessKeyId
OSS_ACCESS_KEY_SECRET=RAM用户AccessKeySecret
OSS_PUBLIC_BASE_URL=https://Bucket的HTTPS访问域名
```

不要把 `.env.production` 提交到 Git，不要在聊天、日志或截图中展示密钥。小程序凭据与微信开放平台“移动应用”凭据不是同一套；当前 Flutter 使用手机号与 Apple 登录，后两项仅为旧版移动端兼容，可保持为空。

填好后启动：

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/server-deploy.sh
```

该脚本会依次执行：配置检查、已有数据库备份、`git fetch/fast-forward`、构建带 Git 提交号标签的镜像、幂等数据库 migration、启动容器、数据库就绪检查。失败时会输出最近日志，并在存在上一镜像时自动恢复 API。

新部署的生产配置模板把 PostgreSQL 数据放在命名卷的 `pgdata` 子目录；Compose 的无配置回退值仍保留历史根目录，避免旧部署升级时悄悄连到空库。部署脚本还会检查 `PG_VERSION`，数据布局与配置不一致时直接停止。

若首次部署已经出现 `postmaster.pid` 和 `pg_wal/xlogtemp` 的 `Operation not permitted`，可执行 `bash deploy/repair-postgres-pgdata.sh`。脚本只在日志精确匹配该首次初始化故障且容器不健康时运行；它会停止失败容器、将半初始化文件移入同一命名卷内的带时间戳归档目录，不删除生产卷。

本项目的 CentOS 7 部署固定使用官方 `postgres:16.15-bookworm`。旧内核与旧 libseccomp 会在 Docker 默认 seccomp 下拒绝新版 Alpine/musl 的写入系统调用路径，因此不能在这台服务器使用 `postgres:16-alpine`。部署脚本会先用独立的一次性卷完成 `initdb`、TCP 就绪和 `SELECT 1`，通过后才会启动生产容器；预检不会挂载生产卷。不要用 `privileged` 或 `seccomp=unconfined` 绕过问题。

如果以后迁移的是已由 Alpine 镜像成功初始化的有效数据库，脚本会默认停止，避免 libc/排序规则变化被静默带入生产。应先备份并评估 collation 与相关索引维护，再由运维人员显式设置 `WANPAN_ALLOW_POSTGRES_LIBC_SWITCH=1`；本次首次部署从未成功完成 `initdb`，不触发该保护。

### Docker Hub 无法访问时

阿里云 ECS 无法稳定拉取 Docker Hub 基础镜像时，不要改用来源不明的公共镜像。仓库支持由 GitHub Actions 在隔离环境中构建 Linux AMD64 镜像、生成 SHA-256 校验文件并发布到与代码提交绑定的 Release。维护者为目标提交推送 `server-bundle-<12位提交号>` 标签后，服务器执行：

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/server-deploy-bundle.sh
```

该脚本会先 fetch 并锁定最新 `main` 提交，下载该提交对应的两份镜像，验证 Release 中的完整 Git 提交号和 SHA-256，再加载镜像并由常规部署流程执行唯一一次 fast-forward。生产环境变量不会进入镜像或 Release。

## 宝塔 Nginx 与 HTTPS

在宝塔中新建站点 `panyan-api.gblh.cloud`，申请 Let's Encrypt 证书并开启强制 HTTPS，然后添加反向代理：

- 代理名称：`wanpan-api`
- 目标 URL：`http://127.0.0.1:3100`
- 发送域名：`$host`

将“客户端请求体限制”调到 `110m`，代理读写超时设为 `180s`。完整参考配置见 `deploy/nginx-panyan.conf.example`；证书路径与宝塔实际生成路径不一致时，以宝塔配置为准。修改后必须检查：

```bash
/www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
```

不要让本项目占用 Crush 直聘的域名或端口。若不用宝塔/Nginx，也可以设置 `WANPAN_COMPOSE_FILE=docker-compose.prod.yml`，由仓库内 Caddy 独立占用 `80/443` 并申请证书。

## 上线验证

服务器本机：

```bash
cd /www/wwwroot/wanpan-diary
curl -fsS http://127.0.0.1:3100/health
curl -fsS http://127.0.0.1:3100/ready
docker compose --env-file .env.production -f docker-compose.server.yml ps
docker compose --env-file .env.production -f docker-compose.server.yml logs --tail=100 api postgres
```

公网：

```bash
curl -fsS https://panyan-api.gblh.cloud/health
curl -fsS https://panyan-api.gblh.cloud/ready
curl -i https://panyan-api.gblh.cloud/.well-known/apple-app-site-association
```

`/health` 验证 API 进程，`/ready` 会实际查询 PostgreSQL；两者都成功才算后端可用。AASA 应直接返回 `200` 和 `application/json`，不能有 HTTPS 地址之间的 30x 跳转。

仓库还提供真实 PostgreSQL 的后端全流程测试。它会创建和删除测试数据，只能连接本地或预发测试库，绝不能对生产库执行：

```bash
npm run test:server:e2e
```

脚本自身也会拒绝在 `NODE_ENV=production` 下运行。

## main 自动部署（沿用服务器现有 GitHub 连接）

GitHub 负责测试、构建和发布镜像包，服务器通过 systemd 计时器每分钟主动检查远端仓库。继续使用服务器原来的 GitHub 认证；不需要把服务器 SSH 私钥上传 GitHub，也不需要新增公网入口。

工作流 [Build server release for automatic deployment](https://github.com/song-ouyang/panyan/actions/workflows/server-image-bundle.yml) 在 `main` 的后端、镜像输入或部署文件变化时自动运行。Flutter、小程序和普通文档变更不触发（`deploy/` 内运维文档也会触发）。合并 PR 和直接 push 都适用。

流程：TypeScript 检查、单元测试、生产依赖审计 → 在独立 CI PostgreSQL 上执行 migration 和 API E2E → 构建 Linux AMD64 镜像 → 完整发布带 SHA-256 的 Release → 为 main 提交写入 `server-ready-<12位提交号>` 标签 → 服务器自动备份、部署并检查本机/公网 `/health` 和 `/ready`。旧的手动 `server-bundle-*` 标签只构建镜像包，不写自动上线标记。

### 一次启用

先把本次工作流和脚本提交、推送到 GitHub 的 `main`。然后在现有服务器的阿里云终端里以 root 执行：

```bash
cd /www/wwwroot/wanpan-diary
git pull --ff-only origin main
bash deploy/install-auto-deploy.sh
```

安装器会先验证生产配置、已部署镜像记录、干净的 main 分支，以及服务器原来的 GitHub 连接能否在无交互、无 SSH agent 的后台环境使用。检查通过后才安装并启用 `wanpan-auto-deploy.service` 与 `wanpan-auto-deploy.timer`。如果现有 GitHub 连接只在交互终端中有效，安装器会停下，需要先修复服务器自己的 Git 认证；不要改成向 GitHub 提供服务器登录私钥。

服务器需已有正常运行的生产环境、Docker Compose、Git、curl、flock、systemd，以及访问 GitHub 仓库和公开 Release 的网络。镜像下载继续使用仓库现有的公开 GitHub Release 路径；仓库若改成私有，需另行配置下载认证。

检查是否启用，以及首次执行结果：

```bash
systemctl is-enabled wanpan-auto-deploy.timer
systemctl list-timers wanpan-auto-deploy.timer
journalctl -u wanpan-auto-deploy.service -n 80 --no-pager
```

日常无需手动部署。镜像发布完成后，服务器通常在下一个一分钟检查周期开始更新。没有新版本时保持安静。GitHub Actions 全绿代表测试和镜像发布成功，服务器日志中的“自动部署完成”及 `.deploy/auto-deploy-success-revision` 才代表上线验证成功。

### 连续提交、失败与暂停

- 服务器读取 main 第一父链上最近的 ready 标签，并比较后端及部署输入。后续只有客户端改动时仍可部署已测试镜像；后续有后端改动时等待新版 CI，不部署过期的后端版本。合并提交也需要自己的测试和 ready 标记。
- 代码、镜像标签、Release 完整提交号必须一致；部署必须快进，拒绝倒退和分叉。开启自动部署后让脚本管理服务器 checkout，日常不再另外执行 `git pull`。
- systemd 不会重叠启动同一个服务，文件锁同时防止与手动部署/回滚重叠。计时器不因下一分钟到来而中断正在运行的备份或 migration。
- 某个版本部署失败/中断后，记入 `.deploy/auto-deploy-failed-revision`，停止自动重试该版本，避免反复迁移。后续新的 ready 版本可以继续尝试。
- 新 API 启动或本机健康检查失败时，部署脚本尝试恢复上一 API 镜像；数据库不自动回退。公网检查失败会记录失败，由运维排查网络/Nginx。修复后清除失败记录并手动执行一次检查；若该镜像已部署，只重试公网检查，不重复迁移。

修复失败原因后，重新检查同一版本：

```bash
cd /www/wwwroot/wanpan-diary
rm -f .deploy/auto-deploy-failed-revision
systemctl start wanpan-auto-deploy.service
journalctl -u wanpan-auto-deploy.service -n 80 --no-pager
```

暂停后续自动检查（不打断正在执行的部署）：

```bash
systemctl stop wanpan-auto-deploy.timer
systemctl disable wanpan-auto-deploy.timer
```

恢复自动检查：

```bash
systemctl enable wanpan-auto-deploy.timer
systemctl start wanpan-auto-deploy.timer
systemctl start wanpan-auto-deploy.service
```

手动执行 `deploy/rollback.sh` 时会先暂停并禁用活动计时器，避免恢复的旧版立即被自动升级。应在修复版本准备好后再恢复计时器。API 镜像回滚不会恢复数据库；migration 必须兼容上一 API，破坏性 schema 变更需要单独安排迁移。

## 以后手动更新：服务器只复制这一条

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/server-deploy.sh
```

脚本自身会拉取 `origin/main`，无需再单独执行 `git pull`。如果服务器 tracked 文件被人工修改，脚本会停止，避免覆盖；`.env.production`、备份和部署状态均已从 Git 排除。

## 备份与回滚

手动数据库备份：

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/backup.sh
```

回滚到上一份健康 API 镜像（不回退数据库）：

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/rollback.sh
```

备份默认保存于 `backups/`、权限为仅 root 可读、保留 14 天。建议另行同步至 OSS。可加入 root 的 `crontab -e`：

```cron
15 3 * * * cd /www/wwwroot/wanpan-diary && bash deploy/backup.sh >> /var/log/wanpan-backup.log 2>&1
```

恢复数据库会覆盖现有数据，必须先停 API、再由运维人员确认备份文件后执行：

```bash
cd /www/wwwroot/wanpan-diary
docker compose --env-file .env.production -f docker-compose.server.yml stop api
gunzip -c backups/要恢复的文件.sql.gz | docker compose --env-file .env.production -f docker-compose.server.yml exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose --env-file .env.production -f docker-compose.server.yml up -d api
curl -fsS http://127.0.0.1:3100/ready
```

## OSS 与客户端配置

- 使用只允许目标 Bucket（推荐进一步限制 `videos/*`）的独立 RAM 用户，不使用阿里云主账号 AccessKey。
- 客户端使用 5MB 分片和 15 分钟预签名 URL 直传 OSS；AccessKey Secret 只存在后端。
- 当前 App 直接保存并展示 `OSS_PUBLIC_BASE_URL` 下的 URL，因此该域名必须可经 HTTPS 读取对象；如果 Bucket 为私有读，需要后续增加 CDN 鉴权或读取签名。
- OSS CORS 至少允许 `PUT/GET/HEAD`，Headers 为 `*`，暴露 `ETag` 和 `x-oss-request-id`。
- 微信公众平台把 API HTTPS 域名加入 `request/uploadFile/downloadFile` 合法域名，把 OSS HTTPS 域名加入 `request/downloadFile` 合法域名。
- Flutter 正式包使用 `PRODUCTION_API_BASE_URL=https://panyan-api.gblh.cloud/api`，并配置微信开放平台移动应用 AppID 和 Universal Link `https://panyan-api.gblh.cloud/wechat/`。

## 常用排障

```bash
cd /www/wwwroot/wanpan-diary
docker compose --env-file .env.production -f docker-compose.server.yml ps
docker compose --env-file .env.production -f docker-compose.server.yml logs -f --tail=200 api postgres
df -h
docker system df
```

不要执行 `docker compose down -v`，`-v` 会删除 PostgreSQL 和本地上传持久卷。

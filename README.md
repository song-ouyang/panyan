# 完攀日记

面向室内抱石的微信小程序 MVP。用户可以按岩馆和换线周期查看 V 级线路，上传完攀视频、记录尝试次数，查看成长统计和月度排行榜，并通过动态、好友和约爬功能认识岩友。

## 目录

- `miniprogram/`：原生微信小程序
- `server/`：Fastify + TypeScript API
- `server/src/db/schema.sql`：PostgreSQL 数据库结构
- `docker-compose.yml`：本地 PostgreSQL 与 API
- `deploy/nginx.conf.example`：生产 HTTPS 反向代理示例

## 已实现

- 微信 `code2session` 登录与 JWT 会话
- 岩馆、换线周期、线路和 V0–V17 难度
- 岩壁照片上传、起步/途经/终点标注、线路投稿与管理员审核发布
- 线路详情叠加显示岩壁标点，并按岩馆换线周期和 V 级筛选
- 线路详情、视频上传、完攀记录和尝试次数
- 公共动态、点赞、评论接口
- 好友申请、接受和好友列表接口
- 约爬创建、列表、加入、退出和取消
- 每条线路的完攀人数、完攀视频点赞榜、岩友月度获赞联赛，以及个人成长数据
- 岩馆管理员创建岩馆、换线周期和线路的 API
- 动态举报、内容待审状态、基础接口限流、用户协议、隐私指引和账号注销
- 小程序内管理员审核中心、好友/约爬/投稿消息通知和个人打卡内容管理
- 城市 → 岩馆品牌 → 多门店 → 门店线路的目录层级
- MP4 完攀视频 OSS 5MB 分片直传、失败重试、合并与实时上传进度条
- Docker、PostgreSQL migration 与示例数据

## 本地启动

要求 Node.js 20+、Docker。

```bash
cp server/.env.example server/.env
# 修改 JWT_SECRET，开发时微信配置可暂时留空
docker compose up -d postgres
npm install
npm --workspace server run db:migrate
npm --workspace server run db:seed
npm run dev:server
```

微信开发者工具导入仓库根目录。开发环境需要在工具中勾选“不校验合法域名、web-view（业务域名）、TLS 版本以及 HTTPS 证书”。

小程序默认请求 `http://127.0.0.1:3000/api`。真机调试时，修改 `miniprogram/utils/config.js` 为电脑局域网 IP 或 HTTPS 测试域名；手机不能通过 `127.0.0.1` 访问电脑。

开发微信登录需要真实 AppID/AppSecret。单独调试 API 时，非生产环境也支持登录 code `dev:任意标识`。

## 生产部署

完整的 Ubuntu 安装、上传、自动 HTTPS 和验证命令见 [`deploy/DEPLOY.md`](deploy/DEPLOY.md)。

1. 准备 Linux 服务器、域名、HTTPS 证书和 PostgreSQL。
2. 复制 `server/.env.example` 为 `server/.env`，填写：
   - `DATABASE_URL`
   - 随机且足够长的 `JWT_SECRET`
   - 微信后台取得的 `WECHAT_APP_ID`、`WECHAT_APP_SECRET`
   - 对外 HTTPS 地址 `PUBLIC_BASE_URL`
   - 正式环境建议设置 `MODERATION_MODE=manual`
3. 构建并启动：

```bash
docker compose build api
docker compose up -d postgres
docker compose run --rm api node server/dist/db/migrate.js
docker compose up -d api
```

4. Nginx 按 `deploy/nginx.conf.example` 反向代理。
5. 把 `miniprogram/utils/config.js` 改成 `https://api.你的域名/api`。
6. 在微信公众平台配置该 HTTPS 域名为 request、uploadFile 和 downloadFile 合法域名。

当前本地上传适合 MVP。正式用户量增加后，应把 `server/src/routes/uploads.ts` 替换为腾讯云 COS、阿里云 OSS 或兼容 S3 的预签名直传，并把当前人工审核适配层接入微信/腾讯云内容安全；不要把大量视频长期放在 API 服务器磁盘。

## 管理员与录入线路

新用户默认为 `user`。首次部署可在数据库中把自己的账号改为管理员：

```sql
UPDATE users SET role='admin' WHERE openid='你的微信openid';
```

之后使用登录 token 调用：

- `POST /api/admin/gyms`
- `POST /api/admin/route-sets`
- `POST /api/admin/routes`
- `GET /api/submissions/pending`
- `POST /api/submissions/:id/review`
- `GET /api/admin/moderation`
- `POST /api/admin/moderation/:id`

线路的 `points` 使用相对坐标（0–1）保存起点、途经点和终点，后续可以直接用于岩壁照片标注功能。

## 上线前必须补充

- 用户协议、隐私保护指引、账号注销和内容举报入口
- 视频/头像/昵称/评论的内容安全审核
- 岩馆管理员后台页面和线路审核流程
- 对象存储、CDN、备份与日志告警
- 接口限流、防刷榜策略，以及完攀视频抽查或岩馆认证机制
- 微信小程序备案、服务器域名备案和合法域名配置

## 质量检查

```bash
npm run check
npm run build
```

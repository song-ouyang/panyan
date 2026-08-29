# 完攀日记

面向室内抱石的跨端产品。用户可以按岩馆和换线周期查看 V 级线路，上传完攀视频、记录尝试次数，查看成长统计和月度排行榜，并通过动态、好友和约爬功能认识岩友。仓库同时保留微信小程序，并新增 Flutter iOS/Android 客户端。

## 目录

- `miniprogram/`：原生微信小程序
- `flutter_app/`：Flutter iOS/Android 客户端
- `server/`：Fastify + TypeScript API
- `server/src/db/schema.sql`：PostgreSQL 数据库结构
- `docker-compose.yml`：本地 PostgreSQL 与 API
- `deploy/DEPLOY.md`：CentOS 7/宝塔服务器部署、备份与回滚说明

## 已实现

- 小程序 `code2session`、Flutter 微信 OpenSDK、Sign in with Apple 与 JWT 会话
- 岩馆、换线周期、线路和 V0–V17 难度
- 岩壁照片上传、起步/途经/终点标注；线路投稿免审并立即发布，附带动态/视频仍按 `MODERATION_MODE` 执行内容审核
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
- Flutter 四 Tab 客户端（岩馆、广场、排行、我的），含品牌门店、线路详情、完攀榜、动态和个人成长
- Flutter MP4/MOV 视频选择、OSS 5MB 分片上传、实时进度、线路立即发布与内容待审/里程碑反馈
- Flutter 白色主题、静止猫咪品牌素材、物理按压反馈、骨架屏、空态和 reduced-motion 适配

## Flutter 客户端

要求 Flutter 3.47+、Dart 3.13+。先按下方“本地启动”运行 API，再执行：

```bash
cd flutter_app
flutter pub get
flutter run
```

开发环境默认 API：

- iOS 模拟器：`http://127.0.0.1:3000/api`
- Android 模拟器：`http://10.0.2.2:3000/api`

需要覆盖地址时使用：

```bash
flutter run --dart-define=API_BASE_URL=http://你的地址:3000/api
```

连接线上 API：

```bash
flutter run \
  --dart-define=APP_ENV=production \
  --dart-define=PRODUCTION_API_BASE_URL=https://panyan-api.gblh.cloud/api \
  --dart-define=WECHAT_MOBILE_APP_ID=微信开放平台移动应用AppID \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://panyan-api.gblh.cloud/wechat/
```

应用允许游客浏览岩馆；进入打卡、动态、投稿、好友、排行和「我的」时会跳转登录，登录后自动回到原操作。JWT 保存在 iOS Keychain / Android 加密存储中，401 会立即清理失效会话。

开发登录不默认自动执行。仅需要调试时显式启动：

```bash
flutter run --dart-define=ENABLE_DEV_LOGIN=true
```

`APP_ENV=production` 下开发登录会被强制关闭。

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

当前服务器（CentOS 7、宝塔/Nginx、`/www/wwwroot/wanpan-diary`）的完整安装、拉取、HTTPS、备份和回滚命令见 [`deploy/DEPLOY.md`](deploy/DEPLOY.md)。生产更新统一执行：

```bash
cd /www/wwwroot/wanpan-diary && bash deploy/server-deploy.sh
```

该脚本会在拉取 `origin/main` 前备份已有数据库，并在构建、migration 后同时验证 API 进程和 PostgreSQL 就绪状态。

生产配置使用仓库根目录的 `.env.production`（从 `.env.production.example` 复制），不要使用开发环境的 `server/.env`。数据库由生产 Compose 创建并保存到命名卷，API 启动前会自动执行幂等 migration；Nginx 反向代理本机 `3100`，PostgreSQL 不对公网开放。

### Flutter 原生登录人工配置

- 微信开放平台：创建「移动应用」，配置 iOS Bundle ID `com.wanpan.wanpanDiary`、Android package `com.wanpan.wanpan_diary` 和正式签名指纹。小程序 AppID/Secret 不能替代移动应用凭据。
- Universal Link：使用 `https://panyan-api.gblh.cloud/wechat/`，确保 `https://panyan-api.gblh.cloud/.well-known/apple-app-site-association` 公网无跳转返回 200 JSON。
- iOS：将 `flutter_app/ios/Flutter/Auth.local.xcconfig.example` 复制为 `Auth.local.xcconfig`，填入微信开放平台移动应用 AppID。Associated Domains 和 Sign in with Apple entitlement 已声明，但 Provisioning Profile 仍需在 Apple Developer 中开启相应 capability。
- Apple 服务端只信任已验签 identity token 的 `sub`，并校验 issuer、audience、有效期和 nonce。
- Android 插件会合并 `${applicationId}.wxapi.WXEntryActivity`，Manifest 已加入微信 package visibility；开放平台的 package/签名不匹配时不会授权成功。
- Android 正式包不再使用 debug 签名。将 `flutter_app/android/key.properties.example` 复制为 `key.properties` 并填写上架密钥；真实密钥、密码和 `*.jks` 已被 Git 忽略。未配置时只生成未签名的构建验证产物，不能上架。

开发环境可使用本地上传；生产环境已经支持阿里云 OSS 分片预签名直传。正式上线应使用受限 RAM 密钥，并把人工审核适配层接入微信/腾讯云内容安全；不要把大量视频放在 API 服务器磁盘。

## 管理员与录入线路

新用户默认为 `user`。首次部署可在数据库中把自己的账号改为管理员：

```sql
UPDATE users SET role='admin' WHERE openid='你的微信openid';
```

岩馆管理员需要同时绑定可管理的门店，避免跨馆查看或审核投稿：

```sql
UPDATE users SET role='gym_admin' WHERE openid='岩馆管理员openid';
INSERT INTO gym_admins(user_id,gym_id)
SELECT u.id,'岩馆UUID'::uuid FROM users u WHERE u.openid='岩馆管理员openid'
ON CONFLICT DO NOTHING;
```

之后使用登录 token 调用：

- `POST /api/admin/gyms`
- `POST /api/admin/route-sets`
- `POST /api/admin/routes`
- `GET /api/submissions/pending`（只用于处理升级前遗留的待审线路）
- `POST /api/submissions/:id/review`（只用于处理升级前遗留的待审线路）
- `GET /api/admin/moderation`
- `POST /api/admin/moderation/:id`

线路的 `points` 使用相对坐标（0–1）保存起点、途经点和终点，后续可以直接用于岩壁照片标注功能。

## 上线前外部配置与运营检查

- 在微信和 App Store 后台提交最终用户协议、隐私政策、注销与举报路径
- 为视频/头像/昵称/评论接入正式内容安全服务，并安排人工复核
- 验证岩馆管理员权限、动态/视频/评论审核与举报处置 SOP
- 启用 OSS/CDN、每日数据库异机备份和日志告警
- 接口限流、防刷榜策略，以及完攀视频抽查或岩馆认证机制
- 微信小程序备案、服务器域名备案和合法域名配置

## 质量检查

```bash
npm run release:check
```

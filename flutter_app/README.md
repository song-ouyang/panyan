# 完攀日记 Flutter

这是完攀日记的 iOS/Android 客户端，与仓库中的微信小程序共用 Fastify API 和 PostgreSQL 数据。

## 已接通的页面

- 岩馆：城市/品牌目录、品牌门店、门店线路、V 级筛选
- 线路：线路资料、完攀人数、视频点赞榜
- 打卡：相册或拍摄视频、尝试次数、说明、上传进度、审核状态和首次难度里程碑
- 广场：动态列表、图片发布、点赞、帖子详情与评论
- 排行：全国积分榜和热门线路
- 我的：个人资料、本月与累计成长数据

四个主 Tab 使用 `StatefulShellRoute.indexedStack`，切换时不重新请求和重建整个页面。详情页保留短过渡，按钮和可点击卡片提供轻量按压反馈，并遵循系统“减少动态效果”设置。猫咪素材保持静止。

## 本地运行

先在仓库根目录启动 API：

```bash
docker compose up -d postgres
npm install
npm --workspace server run db:migrate
npm --workspace server run db:seed
npm run dev:server
```

再启动 Flutter：

```bash
cd flutter_app
flutter pub get
flutter run
```

默认本地地址：

- iOS 模拟器：`http://127.0.0.1:3000/api`
- Android 模拟器：`http://10.0.2.2:3000/api`

真机需要传入电脑局域网地址：

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000/api
```

线上环境：

```bash
flutter run \
  --dart-define=APP_ENV=production \
  --dart-define=PRODUCTION_API_BASE_URL=https://panyan-api.gblh.cloud/api \
  --dart-define=WECHAT_MOBILE_APP_ID=微信开放平台移动应用AppID \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://panyan-api.gblh.cloud/wechat/
```

## 登录说明

开发环境默认也不自动登录。需要调试受保护流程时，使用 `--dart-define=ENABLE_DEV_LOGIN=true`，再在登录页点击「开发账号登录」。生产环境强制关闭该入口。

Flutter App 已接入 `fluwx 6.0.2` 和 `sign_in_with_apple`。微信移动应用 code 会发往 `/auth/wechat-mobile`，不会误用小程序 `/auth/wechat`；Apple identity token 由后端验签。正式发布前仍需完成：

1. 在微信开放平台创建移动应用；
2. 在开放平台填写 iOS Bundle ID、Android package 与正式签名；
3. 配置 iOS Universal Link/AASA 和 Android 正式签名；
4. 在 Apple Developer 为 Bundle ID 开启 Sign in with Apple capability。

JWT 使用 iOS Keychain / Android 加密存储；旧版 SharedPreferences token 会一次性迁移并删除。启动时会调用 `/users/me` 验证会话，任何 API 401 都会清理会话并回到登录。

## 配置项

通过 `--dart-define` 传入：

- `APP_ENV=development|production`
- `API_BASE_URL`
- `PRODUCTION_API_BASE_URL`
- `ENABLE_DEV_LOGIN=true|false`
- `WECHAT_MOBILE_APP_ID`
- `WECHAT_UNIVERSAL_LINK`（例如 `https://panyan-api.gblh.cloud/wechat/`）

## 质量检查

```bash
dart format lib test
dart analyze lib test
flutter test
flutter build ios --simulator --debug --no-codesign
flutter build apk --debug
```

视频上传会在 MP4 文件大于等于 5 MiB 时优先走 OSS 分片流程；本地未配置 OSS 时自动回退为普通上传。

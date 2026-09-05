# 视频压缩与 OSS 续传

打卡和线路投稿的视频在手机准备好后直传 OSS。普通网络失败不再改为向 API 服务器重新上传整个原视频。小于 5MiB 的视频在生产 Flutter 客户端也使用 OSS，最后一片可以小于分片大小。

## 压缩策略

- Flutter 共用 `VideoPreparationService`，使用固定版本 `v_video_compressor 2.2.1` 的 Android Media3 / iOS AVFoundation 编码。默认目标为 H.264 / MP4、最长边 1920、最短边不超过 1080、30fps、视频码率 3Mbps，保留音频，不放大原尺寸。iOS 的码率参数是导出大小预算，实际输出码率和分辨率受系统编码器影响，不保证固定大小。
- 原生插件的 `outputPath` 实际接受目录；适配器使用自己的 staging 目录，验证返回文件并移至约定路径。不能把目标文件路径直接传给插件。
- 不超过 8MiB、分辨率已合适且总码率不超过 3.2Mbps 的 Flutter 视频跳过重复编码。其他视频先尝试编码，验证文件非空与时长完整性；压缩结果更大时选择较小原件，编码失败则明确报错。不会删除或覆盖相册原片。
- 微信小程序调用 `wx.compressVideo`，目标不超过 1080p、30fps、2500kbps。使用 `getFileInfo` 的实际字节数，不能把 `compressVideo.size` 的 kB 当成 bytes。压缩结果验证 MP4 与时长，失败不静默回退大原片。
- 不修改现有选择器时长提示，也没有新增每日配额或全站容量限制。

## 续传行为

1. Flutter 按 API 环境、JWT 用户标识和完整 SHA256 内容摘要绑定上传任务；小程序按 API 环境、服务端用户标识与完整文件 SHA1 摘要绑定。签名 URL 和登录 token 不写入上传检查点。
2. 任务 ID 在发送视频字节之前落盘。Flutter 的压缩产物缓存在应用支持目录，7 天未使用时可回收，另有 512MiB 软上限；活跃上传文件受保护。小程序的准备文件和任务保存 7 天。应用重启后重新选择同一段视频即可尝试续传；本轮不恢复整个发布表单，也不提供操作系统杀进程后的后台传输。
3. 后端 `POST /api/uploads/multipart/status` 分页读取 OSS 已收到的分片。客户端只复用编号、实际大小和 ETag 都有效的分片，包括客户端没有收到成功回包的分片。
4. 每个视频最多 3 路并发，每片 5MiB。单片最多尝试 4 次（首次加 3 次重试），指数退避并每次重新取签名，避免反复使用过期签名。
5. 失败后保留任务，等待所有进行中的 worker 结束再返回。只有后端明确返回 `404 UPLOAD_NOT_FOUND` 才重建任务；网络错误、权限问题和旧后端路由 404 都不会让客户端丢弃任务。
6. 合并操作可重复调用。OSS 已合并但回包丢失时，后端通过精确对象 HEAD 确认结果；重试发布可以复用已完成的视频。完成 URL 再次复用前会向 OSS 查询状态。
7. 上传与发布期间检查账号归属，账号切换后停止旧流程。用户 token 正常刷新仍可恢复同一账号的任务。

缓存被系统清除或超过保留窗口后可能需要重新压缩、重新上传。服务端未完成分片的保留期由 Bucket 生命周期决定；如果 OSS 提前回收了任务，客户端会识别为失效并重新上传。

## 部署顺序

1. 为现有后端 RAM 身份在目标 Bucket 的 `videos/*` 对象范围补充 `oss:ListParts` 和 `oss:GetObject`（HEAD）权限，保留现有上传和终止分片权限。不需要开放 ListBuckets/ListObjects。
2. 先部署后端，再发布 App / 小程序。旧 init、part-url、complete、abort JSON 和 5MiB 分片仍然兼容；无需数据库迁移。
3. OSS 跨域继续允许 `PUT/GET/HEAD`、请求 Headers `*`，暴露 `ETag` 和 `x-oss-request-id`。小程序沿用平台合法域名要求。
4. 使用测试视频核对暂停与续传、完成后 status、重复 complete、弱网重试和不同账号隔离。真实攀岩视频应在 iOS / Android / 微信真机检查手脚细节、方向、音频以及压缩耗时。

本次没有修改线上 RAM、Bucket 生命周期、全站额度、费用告警或生产服务。未完成分片仍可能产生存储费用；可以另行在 OSS 配置只针对未完成分片的生命周期，保留窗口应与预期续传窗口协调，不要给正常已发布视频设置自动删除规则。

## 验证命令

```sh
npm --prefix server run check
npm --prefix server test
npm --prefix server run build
node --test miniprogram/test/*.test.js
cd flutter_app
dart analyze lib test
flutter test
flutter build ios --simulator --debug --no-codesign
flutter build apk --debug
```

参考：[压缩插件](https://pub.dev/packages/v_video_compressor)、[微信官方 API 类型](https://github.com/wechat-miniprogram/api-typings)、[OSS ListParts](https://help.aliyun.com/zh/oss/developer-reference/listparts)、[OSS HeadObject](https://help.aliyun.com/zh/oss/developer-reference/headobject)。

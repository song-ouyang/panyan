# 完攀日记关键动效

这组动效从参考视频中提取的是情绪反馈节奏，不复制其他产品的角色、色彩、文案、奖励系统或界面布局。

统一规格：

- `512 × 512`、`60 fps`、透明背景。
- 一次播放后停在稳定终帧，不循环。
- 只动画 `transform / opacity / trim path`，不用模糊、发光或高密度粒子。
- 动态文字、线路名、难度、尝试次数和积分由 Flutter 真实数据绘制，Lottie 不伪造数据。
- 配色：黑猫 `#171A1E`、珊瑚 `#FF6B52`、珊瑚阴影 `#D94F3A`、向日葵 `#FFC943`、葡萄 `#9A78E8`、薄荷 `#9DD5B0`。
- 系统开启“减少动态效果”时直接展示终帧，去掉位移、回弹和粒子；仍保留一次与结果状态同步的轻量触觉确认。
- 每场只允许一个主元素使用明显缩放回弹；次要岩点、角色与容器使用无超调的淡入/位移落稳。
- 角色分层入场必须通过透明度和位置过渡，不依赖中途 `ip` 直接切入；粒子必须在稳定终帧前完全消失。

动效描述文件：

- [完攀成功](briefs/send-success.md)
- [新 V 级里程碑](briefs/grade-milestone.md)
- [线路发布成功](briefs/route-published.md)
- [排行空状态邀请](briefs/ranking-empty-invite.md)

## 生成与验证

```bash
node design/wanpan-motion/generate_lottie.mjs \
  <官方播放器的 public/projects/wanpan-motion> \
  flutter_app/assets/lottie
```

生成器同时写入官方 Text-to-Lottie 播放器项目和 Flutter 运行时目录，保证预览与真机使用的是同一份 JSON。每次修改后，在官方 CanvasKit/Skottie 播放器检查首帧、动作中点与终帧，再运行 Flutter 测试。

工程接入位置：

- 普通完攀与刷新最高难度：`flutter_app/lib/features/gyms/checkin_screen.dart`
- 线路发布成功：`flutter_app/lib/features/gyms/route_submission_screen.dart`
- 排行空状态：`flutter_app/lib/features/ranking/ranking_screen.dart`
- 一次播放、减少动态效果与静态兜底：`flutter_app/lib/shared/widgets/wanpan_lottie_stage.dart`

官方播放器终帧总览：`previews/wanpan-motion-overview.png`。

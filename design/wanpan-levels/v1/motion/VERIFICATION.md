# Lv.5 徽章获得动效 · 概念验证

2026-09-06，使用正在运行的官方 Text-to-Lottie / CanvasKit Skottie 播放器验证。

- 实际服务：PID `67047`；工作目录 `/private/tmp/wanpan-lottie-official-20260904/lottie-main`；端口 `3030`，由 `lsof` 与 `/__context` 确认。
- 独立场景：`public/projects/wanpan-levels/scene-1/lottie.json`；没有覆盖既有场景。
- 规格：`512 × 512`、`60 fps`、`66` 帧、`1.1 s`；播放一次后保持稳定结果。
- 关键帧：`0` 起势、`27` 轻量回弹峰值、`33` 中点、`65` 终帧均已在官方播放器截图检查；另导出每隔 2 帧的完整运动序列。
- 结果：猫脸、眼睛、岩点、静态徽章数字与外轮廓完整；没有方形底图边界；徽章是唯一回弹主元素；圆环和 8 个稀疏圆点/星屑在第 `54` 帧前全部消失；第 `54–65` 帧完全稳定。
- `/__context` 报告当前场景 `wanpan-levels/scene-1`、`totalFrames: 66`、`fps: 60`。
- JSON 已解析检查；正式播放器副本与本目录 `lottie.json` 使用同一生成器写入。

## 文件

- `lottie.json`：约 14.8 KB 的动画结构。
- `badge-main.png`：1254 × 1254 的原始奶油底概念插画。
- `controls.json`：珊瑚色、向日葵色、圆环线宽、概念演示背景控制。
- `motion-spec.json`：阶段、时长、稳定帧与资产状态。
- `badge-earned-skottie.gif`：官方播放器画面导出的单次 GIF；约 30 fps、1.1 秒动作、1.2 秒额外终帧停留；画面裁切为 1024 × 960，便于直接查看，原 Lottie 舞台仍为 512 × 512。
- `verification/skottie-frame-{00,27,33,65}.png`：包含官方播放器界面的关键帧证据。
- `verification/skottie-preview-final.png`：无播放器面板的稳定终帧。
- `verification/sequence/`：官方 Skottie 导出的 PNG 序列。

## 资产边界

当前插画是含奶油底的 RGB 概念图，动画通过原生椭圆遮罩和奶油场景底色隐藏方角。它不是生产用透明徽章资产。接入任意背景前，应换成真正透明 PNG 或分层矢量；生成器可直接接受透明 PNG，并自动移除概念背景和椭圆遮罩。

没有修改主应用、生产接口、既有动效生成器或 Flutter 运行时资源。动态等级、名称、双条件进度和解锁结果应由真实业务数据与原生文字组件显示，当前图内的 `5` 是固定的 Lv.5 徽章视觉。减少动态效果时直接显示第 `65` 帧，产品页面保持结果直到用户明确关闭。

## 再生成

在仓库根目录运行：

```sh
node design/wanpan-levels/v1/generate-badge-motion.mjs \
  design/wanpan-levels/v1/motion/badge-main.png \
  /private/tmp/wanpan-lottie-official-20260904/lottie-main
```

官方预览：<http://localhost:3030/wanpan-levels/scene-1?frame=65>。官方编辑器的播放按钮会循环预览；产品接入时按照 `motion-spec.json` 使用单次播放并保持终帧。

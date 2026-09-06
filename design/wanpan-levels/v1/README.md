# 完攀日记 · 等级与成长徽章 v1

2026-09-06 的技术方案、等级配置、徽章概念与交互样片。方案与样片使用演示数据；后续已接入 Flutter、小程序及服务端，当前行为和部署状态见 [账户等级与成长徽章](../../../docs/account-levels.md)。下文的样片验证范围保留为设计阶段记录。

## 先看方案

- [技术方案与完整等级表](architecture-notes.md)：含当前代码审计、统计口径、数据库、事务幂等、历史补发、删除撤销和两端接入。
- [等级配置](levels.json)：Lv0 为新岩友起点，无徽章；Lv1–Lv10 对应十枚成长徽章。累计有效完攀日与不同线路数必须同时达标，和 V 难度分别展示。

## 徽章图

- [十枚徽章总览](badge-collection.png)
- [Lv5「攀爬成习」主图](badge-lv5-cream.png)
- [图片生成提示词](image-prompts.md)

设计以黑猫、攀岩岩点和暖奶油色为基础，随等级逐步加入星星、路线和岩峰。保持黑猫角色一致，低等级也有完整的视觉价值，不将起步阶段做成残缺奖品。账户等级不出售，不限制核心攀爬记录功能。

图片使用内置 image_gen 生成。Lv5 独立主图用于本目录的 Lottie 样片，带奶油底色，通过原生椭圆遮罩完成预览。生产客户端采用已确认总览图集及稳定标识 `account-level-01` 至 `account-level-10`，按轮廓运行时裁切并保留源图字节，Lv.10 保留猫耳；实时数字与可访问名称由客户端绘制。当前资料头使用头像等级细圈，完整徽章在进入详情后展示，见 [组件预览](implementation/WIDGET-PREVIEW.md)。

## 获得徽章动效

- [已确认音效与 GitHub 来源](sound-options/README.md)：用户已确认 C「木质小阶梯」为默认声音；主音量 45%、播放增益 0.913，与本版 1.1 秒徽章动效同时开始，约 1.2 秒声音自然播放完尾音。其余三首保留为试听备选。
- [官方 Skottie 渲染的可播放 GIF](motion/badge-earned-skottie.gif)
- [Lottie 与配套图片完整打包](badge-unlock-lottie.zip)
- [Lottie 场景](motion/lottie.json)、[配套主图](motion/badge-main.png)、[可编辑参数](motion/controls.json)
- [时序与素材合同](motion/motion-spec.json)
- [确定性生成器](generate-badge-motion.mjs)
- [官方播放器验证图](motion/verification/)
- [官方播放器验证记录](motion/VERIFICATION.md)

时序为 512×512、60fps、66 帧，共 1.1 秒；徽章从 0.68 倍入场，在 0.45 秒轻微回弹至 1.06 倍，在 0.9 秒完全停稳。圆环和少量粒子消失后保留徽章。结果卡由用户主动关闭，减少动效时直接显示第 65 帧；自动授予权益与播放动画分开。

现有官方 Skottie 播放器路由为 `/wanpan-levels/scene-1`。按下面方式再生成，第二个参数使用当次确认的官方播放器根目录：

```sh
node design/wanpan-levels/v1/generate-badge-motion.mjs \
  design/wanpan-levels/v1/badge-lv5-cream.png \
  <official-player-root>
```

Lottie 的 PNG 与 JSON 需放在同一目录；单独复制 JSON 会缺少徽章。对话内另有相同节拍的产品交互预览，支持重播、减少动效与调整示例成长数据。它使用演示数据，不连接账号接口。

## 设计阶段记录

方案阶段识别到 `sends` 会覆盖重复线路的上次日期，实施时已建立独立完攀事实。11 档门槛已固定为 `wanpan-growth-v1`；后续如需校准必须版本化。休息与断签不会扣进度；本人删除记录、误记及违规撤销按实际有效事实重算，详见技术方案。

本目录早期样片的校验限于方案一致性、图片检查、Lottie 官方渲染和交互预览；客户端测试、数据库迁移和后续生产发布另记在上述实施文档中。

交互预览已通过 35 组双条件等级边界、736/360/320 宽度、领取、重播结束、手动及系统减少动效检查。见 [验证记录](previews/interactive-verification.json)、[手机获得态](previews/interactive-unlock-360.png) 和 [手机成长页](previews/interactive-progress-360.png)。

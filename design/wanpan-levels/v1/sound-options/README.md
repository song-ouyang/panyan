# 徽章获得 · 已确认音效与 GitHub 来源

状态：用户已于 2026-09-06 确认采用 **C「木质小阶梯」**（UI SFX `organic/level-up`），作为获得徽章的默认声音。默认主音量 45%、播放增益 0.913，与 1.1 秒徽章动效同时开始；声音约 1.2 秒，自然播放完尾音。原始文件未剪辑、未变速。

## 已选声音与试听备选

| 选项 | 名称 | 原库文件 | 解码时长 | 适配理由 |
| --- | --- | --- | ---: | --- |
| A | [温暖小星星](uisfx/a-soft-badge.mp3) | `soft/badge` | 约 1.0 秒 | 柔和圆润的上扬三音，贴合黑猫和奶油色徽章 |
| B | [清透水晶](uisfx/b-glass-badge.mp3) | `glass/badge` | 约 1.1 秒 | 更明亮的玻璃铃音，点亮的闪耀感更强 |
| C（已确认） | [木质小阶梯](uisfx/c-organic-level-up.mp3) | `organic/level-up` | 约 1.2 秒 | 自然木质的四段上扬，更突出升级过程 |
| D | [轻快确认](kenney/confirmation_004.wav) | `confirmation_004` | 约 0.5 秒 | 更短的多段上扬，偏游戏里的小庆祝 |

C 的解码时长约 1.2 秒，与徽章动作同时开始，在 1.1 秒动作结束后自然播放完尾音；默认方案已按用户最新选择确定为 C。其余三首保留为可试听的备选。候选筛选依据是上游音色定义、音符编排及本地音频解码、频谱和包络检查；首次筛选推荐 A 的记录仅保留为历史信息。

## 来源与许可

- [UI SFX](https://github.com/romainsimon/uisfx)，固定 commit `a6958b1efd52ee2e430501ca44a5d6b174fa63e4`。已下载完整 GitHub 官方归档，manifest 为 0.4.0、12 组音色、936 个声音（MP3/OGG 两种格式）。音频许可 [CC0](uisfx/LICENSE-AUDIO.txt)，详见 [来源清单](uisfx/source.json)。
- [Kenney Interface Sounds](https://github.com/Calinou/kenney-interface-sounds)，固定 commit `4596a49eaf5a533948d49a47467f606bcdea70ff`，完整 100 个 WAV。音频许可 [CC0](kenney/LICENSE.txt)，详见 [来源清单](kenney/source.json)。
- Git HTTPS clone 返回连接错误，因此使用同一 GitHub 官方 commit 归档获取。完整源库存放在 `/Users/guoba/.codex/asset-sources/wanpan-badge-sounds/`；此目录保留精选四首和 Kenney 一个补充候选。

## 播放与验证

- 同一徽章动作与所选声音从点击时开始；动画 1.1 秒，声音自然播放完，不截断尾音。页面加载不自动出声。
- 默认声音为 C，主音量 45%，播放增益 0.913；试听为便于比较进行了仅播放端的近似 RMS 调整：A 乘 1.0、B 乘 0.931、C 乘 0.913、D 乘 0.47。音频文件保持上游原样。这不是设备声压或感知响度的严格标定。
- 切换、重播、隐藏页面时停止前一音源；减少动效时直接显示徽章，仍允许用户主动试听声音。
- 精选四首均已成功解码为 44.1kHz 单声道，没有达到满幅的采样点。测量值见 [audio-metrics.json](analysis/audio-metrics.json)。MP3 编码填充使解码时长比上游渲染时长约多 40ms，试听标签采用解码时长。
- 原 App 和小程序已有四场 D 双音没有替换；此轮仅为新的账户徽章选音。正式接入时服从用户声音开关、系统静音与现有混音策略。

机器可读声音配置：[candidates.json](candidates.json)。`defaultId` 与 `selectedId` 均为 `C`，`selectedBy` 为 `user`；`recommendedId: A` 及候选中的 `recommended` 标记仅记录首次筛选的历史推荐。

交互试听验证：四首均从播放进入结束状态；快速切换最多一个音源；静音、系统减少动效、关闭后再打开和解码失败重试均已检查；320/360px 无横向溢出。详见 [浏览器验证记录](previews/verification.json) 和 [手机试听画面](previews/audition-360.png)。

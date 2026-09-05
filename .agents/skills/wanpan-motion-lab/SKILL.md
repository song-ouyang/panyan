---
name: wanpan-motion-lab
description: "启动、配置和迭代完攀日记的独立 Flutter 动效实验室。用于预览 Lottie 场景、配置里程碑 V 级序列，或通过仓库生成器创作和再生成动画；不用于运行主应用、连接生产服务或发布构建。"
---

# 完攀动效实验室

在当前仓库根目录工作。实验室唯一入口是 `flutter_app/tool/motion_preview_main.dart`；不要改用 `flutter_app/lib/main.dart`，不要启动生产 API、构建发布包或执行部署。

## 启动

当用户说“启动/打开动效实验室”时，直接执行：

```bash
./.agents/skills/wanpan-motion-lab/scripts/launch_motion_lab.py
```

启动器会实时读取 Flutter 设备，优先选可用的 iOS/Android 模拟器，不保存或猜测设备 ID。没有模拟器且只有一台移动真机时才自动选真机；多台真机时先用 `--list`，再用 `--device DEVICE_ID` 明确选择。

```bash
# 只列出可用的 iOS/Android 目标
./.agents/skills/wanpan-motion-lab/scripts/launch_motion_lab.py --list

# 查看将要执行的安全命令，不启动
./.agents/skills/wanpan-motion-lab/scripts/launch_motion_lab.py --dry-run

# 选择设备并配置里程碑序列
./.agents/skills/wanpan-motion-lab/scripts/launch_motion_lab.py \
  --device DEVICE_ID \
  --grades V2,V4,V5
```

不传 `--grades` 时，实验室使用无数据兜底 `V1,V2,V3`。显式传入时，启动器才将序列作为 `MOTION_MILESTONE_GRADES` Dart define 传给实验室，用于模拟用户最近等级。只接受恰好 3 个不重复、逗号分隔的 `V0`–`V17`。

启动是前台 Flutter debug 会话。使用 `r` 热重载，使用 `R` 热重启，使用 `q` 或 `Ctrl-C` 停止；重新启动前先停掉旧会话，避免重复实例。

## 创作和再生成

- 先读 `design/wanpan-motion/README.md` 和对应的 `design/wanpan-motion/briefs/*.md`。
- 形状、分层、时序和缓动的唯一作者源是 `design/wanpan-motion/generate_lottie.mjs`。不要手工修改生成的 `lottie.json`、`controls.json` 或 `flutter_app/assets/lottie/*.json`。
- 四个场景的声音作者源是 `tools/generate_sounds.py`。不要直接编辑生成的 WAV；修改合成参数后在仓库根目录运行 `python3 tools/generate_sounds.py`，它会把同名资产同步写入 Flutter 与小程序。
- 需要写出生成物时，先确认官方播放器的 `public/projects/wanpan-motion` 路径，再在仓库根目录执行：

```bash
node design/wanpan-motion/generate_lottie.mjs \
  "$WANPAN_LOTTIE_PLAYER_PROJECT" \
  flutter_app/assets/lottie
```

不得自行猜测官方播放器路径。修改生成器前记录已有工作区变更，只改用户指定的场景，不覆盖其他人的动画工作。

## 验证

根据改动范围使用最小有效验证：

```bash
node --check design/wanpan-motion/generate_lottie.mjs
python3 tools/generate_sounds.py
afinfo flutter_app/assets/sounds/send-success.wav
cd flutter_app
flutter test \
  test/motion_sound_assets_test.dart \
  test/wanpan_lottie_stage_test.dart \
  test/checkin_motion_test.dart \
  test/milestone_grade_sequence_test.dart \
  test/motion_preview_test.dart
```

最后在实验室中逐个检查相关场景的首帧、主动作、稳定终帧、独立声音、重播和“减少动效”模式。快切场景时确认上一段声音会停止、相邻预加载页面不会误响。结束后停止 Flutter 会话，并报告实际检查的设备、场景与未能人工确认的项目。

# Flutter 组件预览

以下 PNG 来自真实 Flutter 组件的 widget fixture 渲染，没有连接真实账号或生产 API。个人页与等级进度使用 Lv.4 固定演示数据（30 个攀爬日、119 条不同线路，距离 Lv.5 还差 1 条）；获得徽章画面是独立的 Lv.5 解锁样例。

- `widget-fixture-growth-390.png`：等级入口详情、两项独立进度与收藏起始区域。
- `widget-fixture-profile-level-390.png`：个人页资料头，昵称旁的 Lv 胶囊、保留头像内容的等级双细圈；已移除独立徽章栏目。
- `widget-fixture-profile-level-320.png`：320 px 宽、1.35 倍字号及超长昵称，昵称省略且等级和编辑入口完整保留。
- `widget-fixture-badges-390.png`：徽章收藏已获得与未解锁状态。
- `widget-fixture-badges-mask-audit.png`：10 枚徽章的裁切审阅图，Lv.1–9 为完整画幅椭圆，Lv.10 轮廓保留猫耳。
- `widget-fixture-badge-earned-390.png`：Lv.5 获得徽章的落定画面；使用与收藏相同的图集资源。

截图逻辑宽度为文件名中的 390 或 320 px，2 倍像素输出。为避免 Flutter 测试默认 Ahem 字体遮蔽中文，fixture 临时加载系统黑体及 MaterialIcons；未改变生产主题或增加字体包。资料头 fixture 未配置头像照片，显示姓名占位；实际照片 ImageProvider 保留由 widget test 单独验证。正常与 320 px、1.35 倍字号布局另有 widget tests 验证。临时截图测试已移除，保留业务回归测试。

这组图片用于组件视觉检查，不能代替已安装 App 的登录、网络、真机声音或动作流验收。

运行时裁切保留源 PNG 字节；原图和内置图 SHA256 相同。Lv.1–9 原图深色图案均在圆内，Lv.10 安全轮廓包含完整外耳。最终审阅图未见方形底边或图案/耳朵被截断。

# App Review Guideline 2.1 处理包

## 结论

这次并不是 Apple 认定 App 崩溃或业务违规，而是首次/较少审核记录的开发者账号触发了新 App 补充信息核验。回复说明本身不足以通过：必须同时确保审核专用账号可登录、UGC 举报/拉黑和账号删除可以在审核包中实际操作，并提交最新系统物理设备录屏。

本轮代码已经补齐：

- 动态、评论和用户主页的举报入口；
- 拉黑、取消拉黑及双方动态/评论/互动隔离；
- 应用内账号注销与数据删除；
- 举报后台队列、内容审核、隐私政策和支持联系方式；
- App Review 固定手机号/验证码登录适配层。

## 重新提交前的阻断项

- [ ] 在生产服务器运行 `bash deploy/configure-app-review-login.sh`，并确认脚本输出“发送与登录接口均验证通过”。
- [ ] 用与 App Store Connect 中完全相同的审核手机号和验证码，在蜂窝网络下的真机完整登录一次。
- [ ] 安装本次新构建，完成下方真机录屏。
- [ ] 将 `.mov` 作为 Resolution Center 回复附件，或提供无需登录、长期有效的 HTTPS 下载链接。
- [ ] 将下方 “App Review Notes” 同步填入 App Review Information 的 Notes。
- [ ] 上传新的构建号并选择该构建后再回复审核；不要继续使用缺少举报/拉黑入口的旧构建。

## Resolution Center 英文回复（可直接粘贴）

Replace all `{{...}}` placeholders before sending.

```text
Hello App Review Team,

Thank you for your message. We have completed physical-device QA on the submitted app and prepared the requested information below.

1. Physical-device screen recording

The attached recording was captured on a physical iPhone running the latest available iOS version. It begins with a cold launch and demonstrates the typical user flow, including browsing climbing gyms and routes, passwordless account creation/login, recording a climb, publishing and viewing user-generated content, reporting content, blocking a user, and deleting the account in the app.

Recording: {{ATTACHED_FILE_OR_PUBLIC_HTTPS_URL}}

2. App purpose, target audience, and value

Wanpan Diary (完攀日记) is a climbing journal and community app for indoor bouldering participants, primarily recreational climbers in mainland China. It helps users discover climbing gyms and routes, record completed climbs and attempts, attach photos or short videos, review monthly progress and grade trends, and share climbing updates with other climbers. The app solves the problem of fragmented paper notes, chat messages, and photo albums by keeping route discovery, climbing records, progress, and community interaction in one place.

3. Setup, access, and main feature instructions

No sample files or special hardware are required. Gym and route browsing is available immediately after launch. Account-based actions use passwordless SMS verification; the first successful login automatically creates the account, so there is no separate registration form.

App Review account:
Phone number: {{REVIEW_PHONE}}
Fixed verification code: {{REVIEW_CODE}}

Login steps:
1) Open the My tab and tap Log In.
2) Enter the review phone number above.
3) Tap Get Verification Code. For this dedicated App Review account, the server accepts the request without sending an external SMS.
4) Enter the fixed code above, accept the Terms and Privacy Policy, and tap Verification Code Login.

Main feature paths:
- Browse gyms and routes: Gyms tab > select a gym > select a route.
- Record a completed climb: route detail > Record Send.
- Publish a new route: gym detail > Publish Route.
- Publish a community update: Square tab > coral compose button.
- Report a post: open a post > top-right More menu > Report Post > select a reason.
- Report a comment: open a post > a comment's More menu > Report Comment.
- Report or block a user: open the user's profile > top-right More menu > Report User / Block User.
- Delete the account: My > Account & Privacy > Delete Account and Data > confirm twice. Deletion signs the user out and removes the account-associated data from the primary service.

4. External services, tools, and platforms

- Our first-party Fastify API and PostgreSQL database provide account, gym, route, climbing-record, ranking, friend, feed, reporting, blocking, and moderation functionality.
- Alibaba Cloud hosting and Object Storage Service (OSS) store application data and user-selected photos/videos.
- Alibaba Cloud SMS verification is used for normal phone-number login. The dedicated App Review account uses a fixed server-side code so review access does not depend on SMS delivery.
- The app does not use payment processing, in-app purchases, advertising networks, or AI services in this version.

5. Regional differences

The app's core features and content rules function consistently in all available regions. The current interface and climbing-gym content are focused on Simplified Chinese users in mainland China, and normal SMS login currently supports mainland China (+86) mobile numbers. The App Review account above can be accessed from any region and does not require receipt of an SMS. There are no region-specific paid features or catalogs.

6. Regulated services or protected third-party material

The app is not a financial, medical, gambling, transportation, or other highly regulated service. It does not sell climbing services or present rankings as official competition results. It does not include licensed third-party entertainment content. Gym names and route information are directory/community information, and users must own or have permission to upload their photos and videos. Reporting, blocking, moderation, and support mechanisms are available for safety and rights concerns.

Additional UGC safeguards

New user content is subject to moderation. Users can report posts, comments, routes, meetups, or user accounts; reports enter our moderation queue. Users can block abusive accounts, which removes the blocked account's posts and comments from their experience and prevents further interaction. Our support contact and content rules are available in the app and at https://panyan-api.gblh.cloud/support and https://panyan-api.gblh.cloud/terms.

Privacy Policy: https://panyan-api.gblh.cloud/privacy
Privacy Choices and Account Deletion: https://panyan-api.gblh.cloud/privacy-choices

We have tested these flows on a supported physical iPhone and confirm the app and metadata are complete and ready for review.

Best regards,
Ouyang Song
```

## App Review Information / Notes（精简版）

```text
Wanpan Diary is an indoor-bouldering journal and community app. Review login uses passwordless verification.

REVIEW ACCOUNT
Phone: {{REVIEW_PHONE}}
Fixed code: {{REVIEW_CODE}}
Enter the phone, tap “Get Verification Code,” then enter the fixed code. This dedicated review account does not require receipt of an SMS and works from any region. First login automatically creates an account; there is no separate registration form.

KEY PATHS
Browse: Gyms > gym > route
Record a climb: route detail > Record Send
Publish UGC: Square > coral compose button
Report post: post detail > top-right More > Report Post
Report comment: comment > More > Report Comment
Report/block user: user profile > top-right More
Delete account: My > Account & Privacy > Delete Account and Data > confirm twice

Physical-device demo video: {{ATTACHED_FILE_OR_PUBLIC_HTTPS_URL}}

The app uses our first-party API/PostgreSQL, Alibaba Cloud hosting/OSS, and Alibaba Cloud SMS. No payments, IAP, ads, or AI services are used. The app is not a regulated-industry service and contains no licensed third-party entertainment material. Normal SMS login is +86 only; the review account works without SMS from any region.
```

## 物理设备录屏脚本（约 3–4 分钟）

录屏必须从 iPhone 主屏幕冷启动开始，勿使用模拟器，勿剪掉首次启动。建议开启“勿扰模式”，隐藏通知预览，并确保画面中没有个人短信、真实手机号或其他私人信息。

1. 主屏幕点击“完攀日记”，展示首页和岩馆/线路浏览。
2. 进入“我的”并使用审核专用账号登录；展示首次登录即完成账号创建，不存在独立注册页。
3. 进入某条线路，展示线路详情并完成一次“记录完攀”。
4. 进入“广场”，打开一条他人动态：
   - 右上角“更多” > “举报动态” > 展示原因列表并提交；
   - 评论右侧“更多” > 展示“举报评论”；
   - 点击作者头像进入主页 > “更多” > “拉黑该用户” > 确认；
   - 返回广场，展示该用户内容已被隔离。
5. 使用另一条可演示内容展示发布动态入口；图片选择页可打开后取消，避免上传真实照片。
6. 进入“我的” > “账号与隐私” > “注销并删除账号”，完整展示两次确认并完成删除、退出登录。
7. 重新使用审核账号登录一次，证明审核账号仍然可用，然后结束录屏。

录屏完成后先在另一台设备/浏览器中验证视频可播放且声音、文字清晰，再上传到 App Store Connect。

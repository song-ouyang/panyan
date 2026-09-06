# 账户等级与徽章 v1

`src/services/growth.ts` 是服务端唯一判级入口，版本 `wanpan-growth-v1`，时区 `Asia/Shanghai`。等级同时要求累计有效完攀日和不同线路数达标。Lv0 无徽章，Lv1–10 的 key 为 `account-level-01` 至 `account-level-10`。V 级难度与旧月榜积分保持原合同。

## 接口

- `GET /api/growth/config`：游客可访问（传坏 token 仍返回 401），返回 `rulesVersion`、`timezone`、`levels`。
- `GET /api/users/me/growth-level`：本人快照，含 `revision`、`currentLevel`、`levelName`、`climbingDays`、`uniqueRoutes`、`nextLevel`、两项剩余量和 `backfillStatus`。
- `GET /api/users/me/badges`：`{growth,badges}`，固定 10 枚，状态 `locked | earned | revoked`，保留首次 `earnedAt`。
- `POST /api/users/me/growth-presentations/consume {}`：事务内原子消费汇总庆祝，返回 `{shouldPresent,growth,presentation}`。只有一端得到 `shouldPresent=true`。presentation 含 `id`、`fromLevel`、`toLevel`、`badgeKeys`、`newBadgeCount`、`levelName`、`growthRevision`。
- `POST /api/sends`：可选 `clientRequestId` UUID；`operation=record | edit`，默认 record。record 的服务端确认时刻产生稳定事实，edit 只改原内容、不移 `sent_at`、不加事实。响应保留原字段并添加 `growth`。
- `POST /api/submissions`：沿用 `clientRequestId`，只有附视频并生成 send 时增加成长；也返回 `growth`。
- `POST /api/admin/growth/sends/:id/invalidate {reason}`：仅平台 admin，理由 2–300 字。原子撤销该 send 全部事实、将 send 标记 rejected、重算并记录 actor 与理由。

所有成长写入口先锁 `user_growth`，然后写业务行、事实和奖励。新账号首次读取或写入时，锁内为现存 approved sends 惰性回填一次；写入前先完成回填，避免 upsert 覆盖旧日期。`statement_timestamp()` 固定新事件日期，即便事务等待账号锁跨午夜，也以实际写入语句时刻入账。纯元数据编辑及无视频投稿不会制造成长。

`growth_requests` 以账号 + UUID 去重两个发布入口，校验规范化请求哈希，不同载荷或不同入口复用 UUID 返回 `409 IDEMPOTENCY_KEY_REUSED`。成功重试返回原结果与原成长 revision，不重复写事实、不挪日期；客户端应保留草稿 UUID 及锁定的提交内容，并按 revision 防止旧快照覆盖新数据。旧版投稿没有 hash 时从原记录字段还原并校验。

旧客户端没有 UUID，重复原 send 不追加成长事实；只能将一条首次保存的线路保守记账一次。跨日再攀爬需新版客户端发送新的 UUID。

## 删除、回填与庆祝

本人删除动态时同事务使关联事实失效，再删除 send；等级可降低、相应徽章 revoked。恢复条件后复用原徽章记录，保留首次获得时间，不再次自动庆祝。历史或离线多级奖励合并为最高有效等级的一场，消费与撤销使用同一账号锁。

自然删除线路会使 source 外键置空，稳定的 `route_identity` 与有效事实保留；不把线路换线或归档视为作弊。账号注销采用同一锁顺序，并通过外键清除全部成长数据。请求回执随账号删除，不因删除 send 而丢失，因此重试不会复活已删完攀。

历史只能恢复现存 approved send 保存的最近确认日期，不能恢复旧 upsert 覆盖或用户已删除的中间日期。不做真实物理线路识别，线路 UUID 是去重依据。徽章拥有权和自动消费可去重，消费成功后客户端崩溃仍可能错过动画；客户端详情手动重播不调用授予接口。

## 迁移与验证

增加表的迁移在 `src/db/schema.sql`，可重复运行。先部署包含新 schema 的 API，再发布依赖新接口的客户端。迁移不会访问生产服务或自动导入演示账号。

```sh
npm --prefix server run check
npm --prefix server test
npm --prefix server run build
```

DB E2E 必须显式指定专用本机测试库（名字含 test/e2e/ci），并清空 App Review 短信配置、使用 `UPLOAD_MODE=local`，再运行 `npm --prefix server run test:e2e`。`growth-db-e2e.test.ts` 使用独立 schema 和真正多连接事务，覆盖并发提交、同 ID 载荷冲突、日期稳定性、回填、删除恢复、权限、消费竞态、无视频投稿、旧投稿兼容和失败回滚。

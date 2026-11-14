# v0.2 实际运营接口

所有路径前缀 `/api/v1`。客户/成员使用本系统 Bearer 会话；`/admin/*` 仅服务器生成的 ADMIN_TOKEN。默认所有用户为 customer，生产成员须运营生成邀请并由已登录本人接受，不能从客户端任意选择角色。demo 模式可见切换，仅用于演示。

## 身份与目录

`GET /me` → `{user:{id,name},role:'customer'|'member',playerId:null|string,demo}`；`PATCH /me {name}`。`POST /auth/demo/role {role,playerId?}` 仅演示可用。`POST /admin/players/:id/invitation` 返回 code、expiresAt，一小时有效、单次使用、数据库仅保存哈希；`POST /member/invitation/accept {code}` 完成绑定。

`GET /club` 增加 `configManaged`、`configHash`。品牌文件存在时名称、logo、主体、客服、隐私政策、服务协议等只读，修改返回 `BRAND_MANAGED_BY_CONFIG`。目录仍由 SQLite 管理，服务可包含 `coverUrl,inclusions,requirements`，成员可包含 `avatarUrl,coverUrl`，远程图片仅 HTTPS，可为空。

服务事实可选字段：`platform:'PC'|'mobile'`、`serviceType:'hourly'|'escort'|'review'`、`maps:string[]`、`teamSize:1..4`（服务成员人数）、`gameMode:string`、`billingUnit:'hour'|'session'|'target'`、`rules:string[]`。`variants` 最多 20 项，每项 `{id,title,priceCents,durationMinutes}`，并可覆盖上述事实字段；其余继承主服务。ID 唯一，不支持动态客户端加价。有规格时创建订单必须传 `variantId`，否则 `VARIANT_REQUIRED`；服务器按规格计价/排班，返回冻结的 `serviceSnapshot`（含 variantId/variantTitle/priceCents/durationMinutes/rules 等），历史订单缺快照时返回 null，不回填后来修改的规则。

当前履约仅支持一位服务成员。目录 `teamSize>1` 的商品下单返回 `MULTI_MEMBER_NOT_SUPPORTED`。多人分别接单、档期、交付与分成须后续实现，不能用一位成员的流程冒充双陪。目标类服务字段可保存，但没有自动检测游戏目标或保证游戏收益。

## 时段

`GET /players/:id/availability?date=YYYY-MM-DD&durationMinutes=60` 返回 `{playerId,date,timezone:'Asia/Shanghai',durationMinutes,slots:[{startAt,endAt,available,busy}]}`。时间为 ISO 8601 UTC；日期按上海时区解释，每 30 分钟列出一个可选起点，仅列出完全覆盖服务时长的时段。不会编造“在线”状态。

`GET /member/availability`、`GET /admin/players/:id/availability` 返回 `{playerId,timezone,slots:[{startAt,endAt}]}`。对应 PUT 使用 `{slots:[...]}` 全量替换；最多 200 段，15 分钟至 24 小时、未来 90 天、不重叠，已预约时段不能被移除。生产初始为空；演示显式生成未来 14 天开放时段。

## 履约

订单保留 v0.1 `status`，界面使用 `fulfillmentStatus`：`awaiting_payment → awaiting_assignment → awaiting_acceptance → scheduled → in_progress → awaiting_confirmation → completed`；另有 `disputed`、`cancelled`。演示从 awaiting_assignment 开始，仍 `demo:true,paymentStatus:'unpaid'`。真实订单必须服务端确认已付款才可派单。

订单增加 `assignedPlayerId,commissionBps,memberCents,clubCents,durationMinutes,acceptBy,paymentExpiresAt`。金额单位分，抽成为万分比。客户不能提交金额、抽成或状态。创建时冻结价格/服务时长；派单时冻结当次成员分配和抽成，不重复生成收益。

`POST /admin/orders/:id/assign {playerId,commissionBps?,reason?}` 验证开放时段、服务游戏与真实预留冲突。改派须原因；待接截止为 15 分钟与预约开始时间的较早者。每次请求检查过期待接并释放预留，无后台长轮询进程。

`GET /member/orders` 返回仅派给本人成员的订单；`GET /member/orders/:id` 校验本人指派后返回详情。`POST /member/orders/:id/accept`、`decline {reason}`、`start`、`submit {summary,evidenceUrl?}`。开始仅允许预约前 15 分钟起；交付摘要必填，证据链接仅 HTTPS，服务器不抓取链接。

客户 `POST /orders/:id/confirm {rating:1..5,comment?}` 使单笔收益可结算；`POST /orders/:id/dispute {reason,details?}` 冻结履约与收益。已记录结算的订单不允许自动退款或新争议逆转账本，需人工核对已转出的款项。

订单详情包含 `events:[{id,type,at,actor:{role,name},message}]`、`delivery:{summary,evidenceUrl,submittedAt}|null`、`review:{rating,comment,at}|null`、`dispute:{id,reason,details,status,outcome,createdAt,resolvedAt,resolution}|null`。事件不可由客户端修改。重复确认不会重复收入；重复已完成的动作返回现态或明确冲突。

## 争议、退款与超时

`GET /admin/disputes` 返回争议订单；`POST /admin/orders/:id/resolve {outcome:'resume'|'refund',reason}`。resume 恢复争议前状态；refund 复用微信全额退款，只有已验证成功才取消订单/反转收益。演示退款仅结束模拟履约，明确未发生真实退款。

`POST /admin/orders/expire-unpaid` 每次处理最多 50 个超过 30 分钟的真实未付款订单。可由运营点击或自托管调度器调用；系统不会声称存在未部署的后台定时任务。已发起预支付的订单须查询、关单、查询确认 CLOSED；错误保留待确认状态。已付订单走退款。

## 账本与人工凭据

`GET /member/earnings` 与 `GET /admin/settlements` 返回 `{entries,totals:{heldCents,availableCents,settledCents,reversedCents},currency:'CNY',settlements,demo}`。成员只能看到本人条目与对应份额。条目为每个订单唯一记录，`state` 为 held/available/settled/reversed。

`POST /admin/settlements {entryIds,paymentReference,note?}` 一次最多 100 条，只接收已完成、未争议、真实已付或明确演示的 available 项；禁止混合演示与真实。整批事务写入，不重复结算。相同条目和凭据重试返回原记录。记录 `{id,paymentReference,note,createdAt,memberCents,entryIds,demo,moneyTransferred:false,recordType:'manual_payment_record'}` 表示运营已填写外部转账凭据，API 不转账，也不能证明实际到账。`GET /admin/settlements/export.csv` 安全转义公式单元格。

`GET /admin/overview` → `{counts:{awaitingAssignment,awaitingAcceptance,inProgress,awaitingConfirmation,disputed,paymentOverdue,unsettled},totals:{orderCount,grossCents,paidCents,refundedCents,memberAvailableCents},demo}`，全部数据库计算。

`GET /notifications` 返回本人站内通知数组 `{id,role,type,title,body,orderId,createdAt,readAt}`；`PATCH /notifications/:id/read` 仅标记本人。没有实现微信订阅消息或短信推送。

## 验证与可重现演示

`npm test` 覆盖鉴权、角色邀请、时段冲突、履约、价格冻结、争议、退款、结算幂等、UTF-8 请求、品牌权威与持久化。适配器测试使用本地 RSA/AES 与模拟网络，未完成真实商户验收。

在仓库根目录运行 `node services/api/scripts/generate-demo-snapshot.mjs`：隔离内存数据库、真实 HTTP 调用各角色动作、注入上海晚上 20 点起的测试时钟，导出 `apps/admin/demo-snapshot.json` 与 `services/api/test/fixtures/order-in-progress.json`。没有在静态 JSON 中伪造状态或数值；快照只读，无令牌、密钥与真实个人资料。

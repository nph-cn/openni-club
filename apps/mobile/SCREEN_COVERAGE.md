# 页面与实际状态覆盖

图库清单为 `screenshots/manifest.json`，截图来自实际 Flutter Widget。35 个标识均在 `lib/screens.dart`，由三个截图测试遍历；主流程测试独立运行，不依赖像素基线。所有截图为 390 × 844，`home_android` 使用 Android 平台主题，其余使用 iOS 主题。

| 实际路由 / 组件 | 图库标识 | 状态来源 |
| --- | --- | --- |
| `/` HomePage | home、home_android | 同一目录与 API 导出的进行中订单 |
| `/services` ServicesPage | services | 目录筛选、搜索 |
| `/services/:id` ServicePage | service、service_120 | 60/120 分钟实际规格 |
| `/players` PlayersPage | players | 目录 |
| `/players/:id` PlayerPage | player | 人物、服务与可约时段 |
| `/book` BookingPage | booking、checkout | 选择有效时段后生成核对页 |
| `/orders` OrdersPage | orders、orders_empty | 实际订单集合 / 空集合 |
| `/orders` 未登录分支 | orders_guest | 复用 OrdersSignInPage，正式模式无会话时显示 |
| `/orders/:id` OrderPage | order | API 创建、派单、接受、开始服务导出 |
| `/orders/:id/support` SupportPage | support | 售后表单 |
| `/profile` AccountPage | profile | 未登录个人入口 |
| `/settings` AccountPage | settings | 设置、信息和账号入口 |
| `/announcements` AnnouncementsPage | announcements | 目录公告 |
| `/notifications` NotificationsPage | notifications、member_notifications | 客户空通知 / API 导出的成员通知 |
| `/member` MemberPage | member | 真实成员履约与账本，只读预览 |
| `/member/orders` MemberPage | member_orders | 成员本人订单 |
| `/member/orders/:id` MemberPage | member_order、delivery | 待接单 / 进行中订单交付表单 |
| `/member/availability` AvailabilityPage | availability | API 设置的实际排班 |
| `/member/earnings` MemberPage | earnings | API 导出的本人收入账本 |
| `/welcome` AuthPage | welcome | 登录或游客浏览 |
| `/login` AuthPage | login | 实际登录方式能力；未开放方式禁用 |
| `/login/phone` AuthPage | phone | 手机号、协议与验证码发送 |
| `/login/code` AuthPage | code、code_error、code_verifying | 实际本地挑战、失败请求、等待异步验证 |
| `/legal/privacy` PolicyPage | privacy | 配置的政策文本 |
| `/legal/terms` PolicyPage | terms | 配置的协议文本 |
| ClubBootstrap / ConnectionFailure | home_loading、home_error | 启动骨架 / 可重试错误组件 |

`/states/*`、验证码错误与待验证预览仅在无 API 的本地非生产模式注册或生效。生产忽略预览认证状态；不会改变会话、权限、订单或付款结果。`home_loading` 与 `code_verifying` 的图库“打开 App”链接指向对应可交互正常流程；错误页可实际重试。

验证码预览固定测试码只存在本地内存，界面明确未发送短信；连接 API 使用服务端挑战。错误截图由错误验证码实际产生，待验证截图由相同验证 Widget 等待未完成 Future，不在产品添加延迟。图片截图缓存原 URL 字节，并等待本地图片完成解码。

关键弹层的行为由功能测试覆盖：登录协议、登录后返回且不自动付款、关联微信付款确认、账号注销二次确认。外部微信 SDK 真机授权、真实短信送达和商店审核不能由这些截图或 Widget 测试证明。

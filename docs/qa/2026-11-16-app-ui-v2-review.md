# App UI 重排与图库 v2 验收（2026-11-16）

## 用户反馈
- App 截图 UI 做得不好、太简单；字体太大；图片太少。
- 图库要像 Mobbin：一个 App 的全页面截图多、完整度高。

## App 改动
- 类型比例：页面标题 24 / 详情 22 / 区块 17 / 正文 15 / 次要 12 / 说明 11；数字使用 tabular figures；去掉过大的旧标题。
- 首页重排：问候与进行中服务、精选横幅、游戏分类图卡、精选服务、推荐陪练、公告等模块；服务、详情、预约、订单、我的、成员与认证页面统一使用新卡片、状态色与玻璃导航。
- 截图仍由 Flutter golden 测试经 RepaintBoundary 2x 渲染（780×1688，390×844 逻辑尺寸），不是拼图或截图库素材。
- 修复截图流程暴露的两处溢出：首页骨架横向溢出 18px、成员接单核对头部 Row 20px。
- `flutter analyze` 无问题；`review_screens_test`、`screenshots_test`、`auth_screens_test`、`journey_screens_test`、`product_flow_test`（`--dart-define=OPENNI_CAPTURE_PRODUCT=true`）全部通过并更新 golden。

## 截图扩充
- 新增 `test/page_sections_test.dart`：对 23 个真实页面按固定滚动距离采集「下半屏/后续内容段」，覆盖首页、服务、陪练、预约、订单、个人中心、设置、成员工作台、收入、时间线等，共 37 张新截图。
- Flutter 截图从 64 张增至 101 张；加上小程序 24 张、运营后台 12 张，图库总计 **137 张**真实运行截图。
- 新增截图在 `apps/showcase/catalog.json` 中有标题/角色/流程/说明/排序，构建自动纳入。

## 图库 v2
- 重做为 Mobbin 式 App 展示页：App 介绍与真实统计、用户端/成员端/管理后台切换、按流程分组的大图卡片、搜索、流程与状态筛选、详情逐屏浏览、原图下载。
- 截图数量、流程数、平台数由构建产物计算，不写死。
- 详细页面改造见同目录 `2026-11-16-gallery-v2-review.md`（由图库改版阶段记录）。

## 边界
- 截图设备壳与灵动岛为预览模拟，不是 iOS 真机截图；玻璃为 Flutter/CSS 绘制，不宣称原生 Liquid Glass。
- 示例成员与订单为虚构演示数据；未做真实微信/支付/签名与真机验收。
- 本轮只验证 Chromium/Edge 与 Flutter widget/golden 环境，未做 iOS/Android 真机测试。

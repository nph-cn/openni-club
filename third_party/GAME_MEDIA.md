# 游戏媒体来源与配置

OpenNI 的程序代码采用 MIT 协议。示例目录引用的腾讯、Riot Games 游戏图片及商标属于各自权利人，**不在 OpenNI 的 MIT 授权范围内**。界面截图中出现的游戏素材也不在 MIT 授权范围内。OpenNI 与这些发行商没有合作或背书关系。App 示例保存图片 URL 和来源记录；三角洲视觉专题另外保存官方公开网页原件用于本地设计预览。这些位图和视频均不重新授权为开源资源。发布经营产品前，应按对应官方素材条款核实使用范围，替换为自己有权用于该产品的素材。

官方来源：

- 三角洲行动：[腾讯游戏官网](https://df.qq.com/index.shtml)，页面明确引用 `game.gtimg.cn/images/dfm/cp/a20240906main/` 下的图片。
- 无畏契约：[VALORANT 官方媒体页](https://playvalorant.com/en-us/media/)，素材使用同时受该页链接的 [Riot 法律说明](https://www.riotgames.com/en/legal) 约束。
- 英雄联盟：[官网](https://www.leagueoflegends.com/en-us/) 的游戏标识与 [Data Dragon 官方说明](https://developer.riotgames.com/docs/lol#data-dragon) 的英雄原画。涉及 Riot 产品发布时还需核对 [开发者政策](https://developer.riotgames.com/policies/general)。官方可访问不等于任意商业用途授权。

精确 URL、用途及检视日期记录在 `config/media.sources.json`。示例包含真实游戏官方图片；成员头像仍是有单独来源记录的虚构人物。

## 三角洲视觉专题

2026-11-16 新增 `apps/showcase/delta/`。本地专题包含 4 张官方 3840 像素宽场景、1 张透明小队人物图、2 段视频与对应原帧封面。原始 URL、尺寸及 SHA-256 在 `apps/showcase/delta/assets-manifest.json`；网页 `/delta/sources.html` 提供可点击出处和非官方声明。原件来自 [国服官网](https://df.qq.com/cp/a20240906main/index.html)及[国际官网](https://www.playdeltaforce.com/en/)。没有去除水印或使用 AI 冒充官方游戏画面。

KPR 仅用于观察大画面、层叠字和滚动叙事。OpenNI 官网与截图图库参考 Mobbin 的公开首页和 Explore 页面布局，未保存第三方 App 截图作为产品资产；Mobbin 素材搜索连接器本轮仍不可用。两张新增陪练头像为原创虚构成年人物，记录在 `apps/mobile/assets/demo/GENERATED-2026-11-16.json`。

## 俱乐部如何换图

1. 首次安装：在 `club.json` 的 `initialCatalog.services` 中填写 `coverUrl`（服务封面）、`gameIconUrl`（游戏图标）、`bannerUrl`（游戏横幅），都为可公开访问的 HTTPS 图片地址。
2. 首页横幅写在 `initialCatalog.banners`，每条包含 `id`、`title`、`imageUrl`、`serviceId` 或 `game`、`sortOrder`。`serviceId` 优先跳服务详情，没有时按 `game` 筛选。示例见 `config/demo.club.json`。
3. 数据库首次创建时导入目录。日常更换请在管理后台「首页横幅」编辑/新增/归档，在「服务目录」编辑三种图片地址。保存后客户端下一次加载读取新内容。横幅关联服务归档后会自动隐藏。
4. 品牌配置重新应用不会覆盖已经运营的目录。名称/Logo/经营主体仍由统一品牌配置管理；订单、成员和横幅归运营数据库。

公开接口：`GET /api/v1/banners` 返回按 `sortOrder` 排序且可用的横幅。管理接口：`GET/POST /api/v1/admin/banners`、`PATCH/DELETE /api/v1/admin/banners/:id`，必须管理员鉴权；删除为归档。地址仅接受 HTTPS，不接受带用户名密码的 URL。

横幅示例：

```json
{"id":"banner-delta","title":"三角洲行动","imageUrl":"https://images.example.com/banner.jpg","serviceId":"s1","game":"三角洲行动","sortOrder":0}
```

小程序需把图片域名加入相应的微信合法域名配置并完成真机校验；服务 API 请求域名仍独立配置。网页端需图片服务器允许 CORS 或采用浏览器 HTML 图片渲染。图片失效时更换 URL，不伪造加载成功。Flutter 的截图缓存由 `apps/mobile/tool/cache_catalog_media.dart` 建立在被 Git 忽略的 `.dart_tool/catalog-media` 中，不纳入 MIT 位图资产。

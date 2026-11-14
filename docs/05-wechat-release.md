# 微信小程序：导入、联调、体验与审核

Flutter 本身不会把这个工程直接编译为微信小程序。本仓库的 `apps/miniprogram` 是独立原生实现，服务和订单共用 REST API。页面改动要在两端分别更新。

## 1. 准备小程序账号

在 [微信公众平台](https://mp.weixin.qq.com/) 注册并完成适合业务的主体认证，取得 AppID。服务类目、备案、所需资质与支付能力是否开放，以自己账号后台当前提示为准。不要借用他人的 AppID 或商户号。

AppID 是公开标识；AppSecret 是服务端密钥，不能放在小程序项目中。演示项目不需要 AppSecret；正式微信登录已实现服务端 code 换取身份，按 [微信接入教程](09-wechat-adapters.md) 配置并联调。

## 2. 导入开发者工具

下载 [微信开发者工具](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)，选择导入项目，目录选 `apps/miniprogram`。自己的 AppID 填在统一 JSON 的 `distribution.wechatMiniAppId`，生成器自动更新项目配置；空 AppID 仅用于工具允许的游客预览。

启动本地 API，在统一 JSON 的 `endpoints.apiBaseUrl` 填 API 地址并重新生成。小程序配置读取生成文件，不需要改 `utils/config.js`。模拟器联调可按开发工具允许的设置临时忽略合法域名校验，仅用于本机测试；正式构建与真机验收必须恢复校验。

## 3. 配置真实 HTTPS API

在小程序后台「开发管理 → 开发设置」检查服务器域名入口，将 API 的 origin（例如 `https://api.example.com`，不带 `/api/v1`）加入 request 合法域名。图片/上传/下载/websocket 按实际使用分别配置。确保 HTTPS 证书链完整且服务端可访问。[微信网络说明](https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html)

本次自动核查无法读取微信文档页面，因此不能代替你账号内的最新域名、备案或类目要求。特别是 `.im` 是否可用于该账号的合法服务器域名，应在正式投入前用微信后台和托管服务商核验；必要时使用符合要求的独立 API 域名，展示网站仍可保留原域名。

## 4. 联调第一笔预约

在模拟器体验：首页 → 服务详情 → 预约 → 订单详情 → 取消。然后点击「预览」用手机扫码，重复同样流程。手机不能连接电脑的 localhost，联调时使用可访问的测试 HTTPS API。

确认失败和空状态都能正常返回；重复提交不会产生两笔相同订单；不允许读取其他用户订单；用户退到后台再进入时状态能刷新。演示订单不代表付款。

## 5. 上传体验版与提交审核

在开发者工具上传版本，填写版本号和变更说明。到微信公众平台选择该版本设为体验版，邀请内部体验人员。完成主体、类目、隐私保护指引、备案和实际功能所需的资质后，再提交审核。

隐私保护指引填写实际收集的数据和用途；只在用户触发需要的操作时申请权限。真实登录、手机号或支付未接入时，不应给审核人员宣称已经实现。审核通过后还需在后台发布，体验版上传成功不等于已上线。[微信小程序官方入口](https://developers.weixin.qq.com/miniprogram/introduction/)

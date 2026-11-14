# OpenNI 微信小程序

原生微信小程序，15 个页面，共用 `services/api`，无第三方 npm 运行时依赖。客户可选服务规格、查看真实排班、提交预约、确认交付和申请售后；成员可接单、拒单、履约、提交记录、维护时段和查看账本。

## 本地预览

1. 从仓库根目录运行 `node scripts/configure-club.mjs --apply config/demo.club.json`。品牌、配色、AppID、API 地址统一生成到 `utils/brand.generated.js`，不要手动维护第二份配置。
2. 在 `services/api` 执行 `npm start`（Node.js 22.13+；默认 8787）。
3. 微信开发者工具导入本目录。生成的 `touristappid` 仅用于本地预览，正式版必须使用自己的 AppID。
4. 默认演示配置使用 `http://localhost:8787/api/v1`。开发工具连接本机 HTTP 时可启用本地调试的「不校验合法域名、web-view、TLS 版本以及 HTTPS 证书」。仅限本地开发；手机上的 localhost 指手机自己，真机应使用已配置 request 合法域名的 HTTPS API。
5. 在「我的」切换显式演示身份。客户提交预约后，由管理后台派单，再切换对应成员接单；交付后由客户确认。生产环境没有任意角色切换，成员身份通过运营发放的邀请绑定。

## 页面与数据

客户页面：home、services、service、players、player、booking、orders、order、profile、announcements、settings、notifications。

成员页面：member、availability、earnings；order 根据服务器身份显示成员履约操作。

服务金额、规格与规则由服务器冻结。客户端只提交服务与规格 ID，不计算价格或分成。预约使用幂等标识；排班和占用冲突由 API 校验。消息、交付记录和收入都读取真实 API，不在客户端制造成功状态。当前一次预约只支持一位服务成员；多成员订单会明确拒绝，不能把“团队人数”当作已经完成多人派单能力。

演示会话 24 小时过期；所有演示页面有可见标识，不发起真实扣款。人物图片是原创虚构成年人，仅在 demo 使用；正式模式优先使用运营设置的 avatarUrl，没有图片时显示姓名首字。出处见 `assets/demo/PROVENANCE.md`。

## 正式配置与验收

在统一俱乐部配置中填写正式品牌、HTTPS API、小程序 AppID、经营主体、客服和政策正文，设置 production 与 demoData=false 后重新生成。客户端以 wx.login 获取 code，通过 `/auth/wechat` 换取应用会话；订单页请求 JSAPI 参数后调用 wx.requestPayment，随后重新读取服务器订单。SDK 成功回调不会直接把订单标成已支付。

服务器需要微信身份与商户配置；私钥、AppSecret、API v3 密钥和管理员令牌不得进入小程序包。上线仍需微信主体和业务审核、真机登录、支付与退款验收。账本中的人工结算凭据不代表系统自动转账。

## 验证

运行 `node --test test/*.test.cjs`。测试覆盖15页文件与模板、真实本地API加载/预约、成员接单到交付确认/账本、排班/通知，以及 production 登录/支付逻辑（上游及 SDK 使用测试夹具）。

2026-11-15 已在微信开发者工具 Stable 2.01.2510290、基础库3.7.12、游客模式编译并检查15页。原生UI真实执行客户提交预约→订单详情/列表，以及成员待接单→确认接单→已排期；收入与时段页面从本地API读取。`screenshots/manifest.json`列出15张实际屏幕截图；截图只裁掉开发工具外框，保留状态栏和底部安全区。没有进行真实微信身份、真实支付退款或手机真机验收。

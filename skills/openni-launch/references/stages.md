# 阶段手册

本 Skill 与 OpenNI Club 仓库配合使用。以下路径相对于仓库根目录；复制技能到个人目录后仍然读取用户选定仓库中的文件。

| 当前需求 | 先读 | 操作及通过标准 |
| --- | --- | --- |
| 第一次体验 | docs/01-quickstart.md | 检查 Node/Flutter；启动 API 和 App；一笔演示预约可查询并取消 |
| 换品牌 | docs/02-brand-and-config.md、docs/10-single-config-workflow.md | 一份配置+Logo，check→plan→apply；各端名称/主题/图标一致，秘密不进入public |
| 生成安装包 | docs/10-single-config-workflow.md | release-club真实执行工具链，保存阶段结果/产物hash；失败不称上架，审核与真机单独验收 |
| 接域名、部署 | docs/03-deployment.md | 检查现有记录与证书；只修改目标域名；NS Active + HTTPS API + 客户端请求验证 |
| iOS / Android | docs/04-mobile-release.md | 签名属于俱乐部；release 构建 + 真机测试 + 审核材料；未通过审核不得称已上线 |
| 微信小程序 | docs/05-wechat-release.md | 自有 AppID，HTTPS 合法域名和当前控制台条件；模拟器与真机都通过 |
| 登录 / 支付 / 短信 | docs/06-integrations.md | 先确认适配代码存在；不存在则明确实现工作；供应商成功/失败/重复通知都联调 |
| 已有微信商户与 AppID | docs/09-wechat-adapters.md | 核对小程序/原生 AppID、商户绑定、签名私钥和可信平台公钥；通过脱敏配置检查后做真机验收 |
| 准备开放用户 | docs/07-release-checklist.md | 有证据地逐项通过，或列出阻断；不能把客户填写“已完成”当作测试证据 |

## 定位错误

接口不可访问：先检查 `/health`、端口、客户端 API_BASE_URL、HTTPS 与 CORS；不把请求错误静默切回演示。手机上的 localhost 是手机本身，Android 模拟器宿主机通常用 10.0.2.2。

订单不一致：确认是否切换了演示身份、API 模式或数据目录；SQLite 持久化目录与启动工作目录有关。先备份，再检查迁移；不能删除数据目录修复。

签名失败：区分构建工具缺失、签名团队/Bundle ID 不匹配、证书或 profile 失效。不要把密码或证书内容打印出来，不从陌生来源下载签名材料。

支付失败：确认真实适配是否存在。若没有，返回明确阻断；若有，检查脱敏错误码、商户/AppID 绑定、服务端订单及回调验签，不能只检查客户端弹窗。

## 教学输出样式

每一步只给完成当前目标所需的命令。命令需写明工作目录；example.com 明确要求换成用户域名。解释“看到什么才算通过”，然后验证当前授权范围内能验证的结果。让经营者自己保存密钥，报告只写密钥配置是否存在、权限是否足够和验证结果。

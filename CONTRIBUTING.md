# 参与 OpenNI Club

先运行本地演示，并阅读 PRODUCT.md、DESIGN.md 和 CONTRACT.md。修改客户端/API 时同步约定；微信小程序和 Flutter 不会自动互相更新。

提交前运行对应范围的验证：API 与适配器 `node --test services/api/test/*.test.mjs services/integrations/test/*.test.mjs`；Flutter `flutter analyze` 和 `flutter test test/flows_test.dart`；小程序在开发者工具与真机检查页面流转。增加真实集成时提供成功、失败、重试和权限场景，不能只保留供应商调用的成功分支。

使用虚构测试身份和示例联系方式。不要提交 `.env`、私钥、证书密码、真实 SQLite 数据库、用户订单、开发工具个人配置或未授权游戏素材。新增依赖/字体需要保留许可证与来源。

界面变更应更新对应真实页面截图和页面目录。PR 说明改动后用户能做什么、如何验证、哪些平台尚未测试。不要把静态页面、签名检查或模拟付款描述为完成生产流程。

贡献的项目代码与自编文档按仓库 MIT 许可分发；第三方依赖保留自身许可。

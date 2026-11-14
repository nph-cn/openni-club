# 域名、Cloudflare 和服务器部署

本章把三件事分开完成：DNS 告诉访客去哪里；网站展示产品；API 保存订单。把域名加入 Cloudflare 不等于已经部署网站或 API。

## 1. 将已有域名的 DNS 托管到 Cloudflare

`openni.im` 这样的已注册根域名可按 Cloudflare Full setup 接入；不必把域名注册商转到 Cloudflare。域名仍在原注册商续费，DNS 在 Cloudflare 管理。[官方 Full setup 文档](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/)

1. 登录自己的 Cloudflare，进入 Domains，选择接入域名，输入根域名，不带 `https://`。
2. 选择适合的套餐；初期可评估 Free。检查扫描得到的 DNS 记录。若有邮箱，先保存 MX、SPF、DKIM、DMARC；扫描不保证找全。
3. Cloudflare 分配两个名称服务器。逐字复制你这次看到的值，不复制别人教程中的示例。
4. 登录域名注册商 → 域名详情 → Nameservers / 名称服务器 → Custom / 自定义，替换原名称服务器，保存。
5. 返回 Cloudflare 检查状态，等待 Active。使用 DNS 查询工具查看 NS，不能仅凭页面显示“已保存”认定全球生效。
6. 如果旧 DNSSEC 存在，按 Cloudflare 迁移说明处理旧 DS 记录，避免无效签名导致解析失败；不要臆造 `.im` 支持某种 DNSSEC 配置。

只修改目标域名。邮件和其他子域记录需要保留；没有源站时先不填写随意的 IP。Cloudflare 的代理和缓存规则应对订单、登录、个人信息接口禁用缓存。

## 2. 推荐的部署边界

| 服务 | 示例地址 | 运行位置 |
| --- | --- | --- |
| 公开网站 / 截图库 | `https://example.com` | 静态网站托管 |
| API | `https://api.example.com/api/v1` | 支持 Node 24 与持久化磁盘的服务器/容器 |
| 管理后台 | `https://admin.example.com` | 静态托管或同源发布；API 仍需管理员鉴权 |

本 API 使用 Node.js SQLite 文件，不能直接当作 Cloudflare Worker 或没有持久化磁盘的函数部署。若未来迁移 D1，需要专门适配数据库层和事务语义。单机 SQLite 适合初期独立俱乐部；多副本部署不能各写各的本地数据库。

## 3. 部署演示 API

先在隔离测试服务器验证。安装 Node 24，上传源代码，创建服务器专用 `.env`，设置固定 DATA_DIR，创建随机管理员令牌和精确 CORS_ORIGINS。禁止把 .env 放进网站公开目录。

从仓库根目录启动：

```sh
node --env-file=.env services/api/src/server.mjs
```

长期运行使用宿主机服务管理或容器重启策略，不依赖你电脑的终端。若使用项目 Dockerfile，构建前先读文件确认工作目录、暴露端口和数据目录，再将 SQLite 目录挂载到持久化卷；不能只把容器镜像当备份。

配置反向代理终止 HTTPS，将 API 请求转给本地端口。Cloudflare 到源站也使用有效证书，SSL/TLS 采用 Full (strict)；不要用关闭证书验证解决连接问题。服务器防火墙只开放必要入口。

连接后检查：

```sh
curl --fail https://api.example.com/health
curl --fail https://api.example.com/api/v1/club
```

这里的 example.com 必须换成你自己的域名。浏览器可打开接口不代表移动端已经正确配置，继续用客户端完成预约、查询和取消。

## 4. 从演示到正式服务

`production` 模式关闭演示身份，按实际配置启用小程序或原生微信登录；支付使用独立开关。代码中已有下单、验签、查单、全额退款及退款状态同步。配置方式见 [微信接入教程](09-wechat-adapters.md)，真实商户与设备验收见 [验收表](07-release-checklist.md)。匿名生成的 demo 身份不能用于真实经营数据。

生产环境至少需要：可靠身份、权限、有效 HTTPS、服务端密钥、私密数据卷、备份、日志脱敏、限流和错误监控。域名是否适合中国大陆部署/小程序合法域名，以及备案材料，以所选托管商、微信后台和 [工信部备案系统](https://beian.miit.gov.cn/) 核验为准；不要把 `.im` 可以解析理解成一定满足备案/平台准入。

## 5. 更新与恢复

更新前记录当前版本并备份数据库；SQLite 开启 WAL 时不能只随手复制主文件，使用 SQLite 一致性备份工具或停写后完整备份。保留加密的离机副本，定期在空测试目录恢复并核对订单数量。每次升级先测试迁移，再切换服务；失败时回退应用与匹配的数据库版本。不要用删除 data 目录“修复”线上错误。

## 6. 使用 Docker Compose 部署 HTTPS API 与后台

在有公网 IP 的服务器安装 Docker Engine 和 Compose。给 `api.你的域名` 添加 A 记录，若配 AAAA 则 IPv6 必须也能到这台服务器。首次签发证书可先用 Cloudflare DNS only；确认源站证书正常后再开启代理，并使用 Full (strict)。80/443 需要可从公网到达，不能已有其他服务占用。[Caddy 自动 HTTPS 要求](https://caddyserver.com/docs/automatic-https)

在仓库根目录先运行 `npm ci`（生成器与品牌向导使用这些依赖），再执行 `cp deploy/.env.example deploy/.env`。编辑 `deploy/.env`：填 `API_DOMAIN`（只填主机名）、证书联系邮箱、至少 32 字符随机 `ADMIN_TOKEN`、真实后台 HTTPS origin 和微信配置。`.env` 不放在网站目录；需要支付时把 PEM 放进 `deploy/secrets/`，允许容器 node 用户读取，限制无关用户访问。

先按 [单配置教程](10-single-config-workflow.md) 生成自己的 `generated/club/`。Compose 只读挂载这个目录，API 自动读取公开品牌和首启 seed，已有数据库不会被重新初始化。更换配置后重新生成并重启 API；不要让演示配置覆盖正式品牌。

在 `deploy` 目录运行：

```sh
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

`config --quiet` 只校验、不打印解析后的秘密。只向宿主机开放 80/443；API 的 8787 仅容器网络可访问。SQLite 保存在命名卷 `openni-club_api-data`，证书在单独持久化卷；重建容器不清空它们。不要使用 `down -v` 作为日常重启命令。

打开 `https://api.你的域名/health`，再打开 `https://api.你的域名/admin/`，用管理员令牌连接同一 API。品牌向导位于同源 `/studio/`，导出的文件仍需生成、检查和部署，不会直接覆写运行中的数据库。俱乐部目录先替换演示内容，再做真实微信联调。公开截图网站与 Web 客户端可独立部署仓库 `dist/`；本 Compose 提供 API、运营后台和品牌向导，不会自动构建或发布应用商店包。

如果证书申请失败，检查 DNS、端口和 Caddy 日志；不关闭 TLS 验证。可运行 `docker compose logs --tail=50 caddy`；分享日志前确认没有私人数据。更新用 `docker compose up -d --build`，更新前先做一致性备份。

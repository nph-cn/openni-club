# 域名与服务器

本章使用仓库自带的 Docker Compose，在一台服务器上运行 API、运营后台和品牌配置页。先完成 [本地启动](01-quickstart.md) 与 [生成应用配置](10-single-config-workflow.md)。

## 1. 确定访问地址

下文用 `api.example.com` 表示你的 API 域名，操作时全部替换为自己拥有的域名。

| 用途 | 地址示例 |
| --- | --- |
| API 健康检查 | `https://api.example.com/health` |
| 客户端 API 地址 | `https://api.example.com/api/v1` |
| 运营后台 | `https://api.example.com/admin/` |
| 品牌配置页 | `https://api.example.com/studio/` |

服务器需要公网 IP、Docker Engine 与 Compose，并允许公网访问 80、443 端口。API 使用 SQLite 文件，必须保留持久化磁盘；不能直接部署成没有持久化磁盘的云函数或 Cloudflare Worker。

## 2. 将 DNS 接入 Cloudflare

已有的 `openni.im` 这类根域名可以使用 Cloudflare Full setup。域名仍在原注册商续费，名称服务器和 DNS 记录交给 Cloudflare 管理。[Cloudflare 官方接入说明](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/)

1. 登录自己的 Cloudflare，在 **Domains** 中添加域名，只填写根域名，不带 `https://`。
2. 选择套餐并核对已有记录。如果域名有邮箱，保存原来的 MX、SPF、DKIM、DMARC 记录。
3. 复制 Cloudflare 分配的两个名称服务器。每个域名分配的值可能不同，使用自己控制台中的值。
4. 打开注册商的域名详情，找到 **Nameservers / 名称服务器 → Custom / 自定义**，填入这两个值并保存。
5. 返回 Cloudflare 等待域名状态变为 **Active**，再用 DNS 查询工具核对 NS 记录。
6. 如果原域名启用了 DNSSEC，按 Cloudflare 的迁移步骤处理旧 DS 记录，避免解析失败。

接着进入 Cloudflare 的 **DNS → 记录 → 添加记录**：

| 字段 | 填写内容 |
| --- | --- |
| 类型 | `A` |
| 名称 | `api` |
| IPv4 地址 | 服务器的公网 IP |
| 代理状态 | 首次配置先使用「仅 DNS」 |
| TTL | 自动 |

**检查结果：** `api.你的域名` 能解析到服务器公网 IP。没有 IPv6 服务时不要添加 AAAA 记录。

## 3. 准备服务器文件

连接服务器后，按服务器系统安装 [Docker Engine](https://docs.docker.com/engine/install/)、Compose、Git 和 Node.js 24。执行以下命令检查：

```sh
docker --version
docker compose version
node --version
git --version
```

下载代码并安装生成器依赖：

```sh
git clone https://github.com/nph-cn/openni-club.git
cd openni-club
npm ci
```

将自己的配置包放入 `config/`。如果还未制作，先使用 [品牌配置页](https://openni.im/studio/) 导出，再按 [配置教程](10-single-config-workflow.md) 放置 `club.json` 与 Logo。检查并生成：

```sh
node scripts/configure-club.mjs --check config/club.json --mode production
node scripts/configure-club.mjs --apply config/club.json --mode production
```

**检查结果：** `generated/club/` 中出现 `public.json`、`seed.json`、`manifest.json` 和政策页面。正式校验未通过时，按输出补齐真实经营资料和平台身份，不要通过切回测试模式绕过。

## 4. 填写服务端配置

在仓库根目录执行：

```sh
cp deploy/.env.example deploy/.env
```

用编辑器打开 `deploy/.env`，逐项填写：

| 字段 | 填写方法 |
| --- | --- |
| `API_DOMAIN` | `api.你的域名`，不带协议或路径 |
| `ACME_EMAIL` | 接收证书通知的邮箱 |
| `API_MODE` | 正式环境保持 `production` |
| `ADMIN_TOKEN` | 至少 32 字符的随机管理员令牌 |
| `CORS_ORIGINS` | 允许访问 API 的完整网页来源，如 `https://api.你的域名`；多个来源用逗号分隔 |
| `WECHAT_*` | 按 [微信登录与支付](09-wechat-adapters.md) 填写自己的平台信息 |

将文件里的 `api.example.com` 回调地址换成自己的 API 域名。支付配置未完成时，保留 `WECHAT_PAY_ENABLED=false` 和 `WECHAT_NATIVE_PAY_ENABLED=false`。

需要支付时，把商户 PEM 文件放进 `deploy/secrets/`。环境变量中的 `/run/openni-secrets/` 是容器内的路径，对应这个目录。确认容器的 node 用户能读取文件，且无关用户不能读取。

`deploy/.env`、管理员令牌和私钥不放进公开网站或 Git。后台连接时需要的 API 地址是公开信息，管理员令牌是秘密信息。

## 5. 启动服务

进入部署目录执行：

```sh
cd deploy
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

`config --quiet` 只校验配置，不打印解析后的秘密。Caddy 会申请 HTTPS 证书并把 API 请求转发到容器内部的 8787 端口。

**检查结果：** `api` 为 `healthy`，`caddy` 为运行状态。浏览器打开 `https://api.你的域名/health`，能看到健康状态 JSON。

若准备启用 Cloudflare 代理，先确认源站证书已经正常，再把记录切换为「已代理」，SSL/TLS 采用 **Full (strict)**。不要用关闭 TLS 校验解决证书错误。[Caddy HTTPS 要求](https://caddyserver.com/docs/automatic-https)

## 6. 连接后台和客户端

打开 `https://api.你的域名/admin/`，点击 **连接俱乐部**，填写：

- API 地址：`https://api.你的域名/api/v1`
- 管理员令牌：刚才在 `deploy/.env` 中设置的 `ADMIN_TOKEN`

连接后进入服务目录，填写自己的服务、规格与价格；再维护成员、排班、公告和图片。不要继续使用项目自带的示例经营资料。

在 `config/club.json` 的 `endpoints.apiBaseUrl` 填写同一 API 地址，重新生成配置并构建客户端。正式模式需要真实微信身份；先按微信章节完成登录，再验证下单、派单、接单和订单查询。

## 6.1 构建并发布公开静态站

公开网站、画廊、品牌配置页（studio）、文档（guide）与 Web 演示（demo）由 `dist/` 静态目录提供，不随 Compose 自动生成。先在 `apps/mobile` 产出 Web 演示产物，再在仓库根目录打包：

```sh
cd apps/mobile && flutter build web && cd ../..
npm run build
```

`npm run build`（`node scripts/build.mjs`）会把 `apps/showcase`、`apps/admin`、`apps/studio`、`docs` 与 Web 演示汇总到 `dist/`，并校验画廊截图齐全。把 `dist/` 部署到任意静态托管（对象存储、Nginx 或 CDN）即可；后台与品牌配置页按实际来源配置 CORS。

**检查结果：** `dist/index.html`、`dist/studio/`、`dist/guide/`、`dist/demo/`、`dist/admin/` 与 `dist/screens/` 均存在；画廊截图可打开。

本地预览静态站：在仓库根目录 `cd dist && python3 -m http.server 8099`，访问 `http://127.0.0.1:8099/`（展示站）、`/demo/`（Web 演示）、`/admin/`、`/guide/`。

> 本地 Web 演示预览环境备注：Flutter Web 首帧依赖浏览器的 WebGL/Canvas 合成。若在某台机器的 Chromium 里演示页停在启动占位、看不到画面，先在 Safari 或其他浏览器打开同一地址对照；同一产物在 Safari 能出帧即说明应用代码与产物正常，问题在本机 Chromium 的 GPU/合成环境（驱动、ANGLE 或标志位），不要据此判断客户端代码有缺陷。线上用户环境多样，最终以线上静态托管地址在真实浏览器的打开结果为准。

**检查结果：** 后台能读取自己的俱乐部目录；客户端登录后能查询自己的订单；另一个账号不能读取前一账号的订单。

## 7. 更新与备份

数据库位于 Compose 命名卷 `openni-club_api-data`。证书使用独立的 Caddy 数据卷，普通容器重建不会清空它们。日常重启不要使用 `docker compose down -v`。

更新前先记录当前版本并做一致性备份。SQLite 开启 WAL 时，使用 SQLite 一致性备份工具，或停止写入后完整备份；不要只复制正在写入的主数据库文件。定期在测试目录恢复一次，确认订单和账本能正常读取。

更新代码与配置后，在 `deploy/` 执行：

```sh
docker compose up -d --build
docker compose ps
```

**检查结果：** 服务重新变为健康状态，历史订单仍在。若更新失败，恢复之前的应用版本与匹配的数据库备份，不要删除数据目录来排错。

## 常见问题

| 现象 | 检查项 |
| --- | --- |
| 无法签发证书 | 域名是否解析到服务器、80/443 是否可从公网访问、是否被其他服务占用 |
| API 容器退出 | `docker compose logs --tail=50 api`；检查环境配置、数据卷权限与 Node 版本 |
| 后台无法连接 | API 地址是否包含 `/api/v1`、令牌是否一致、`CORS_ORIGINS` 是否包含后台完整来源 |
| 小程序提示非法域名 | 在微信后台填写自己的合法服务器域名，并使用有效 HTTPS 证书 |
| 更新后出现新的空目录 | 检查 Compose 项目名、数据卷和 `DATA_DIR`，不要把新建卷误认为原数据丢失 |
| 公开网站没有启动 | 此 Compose 提供 API、后台和品牌配置页；公开网站与 Web App 需另外构建并发布 `dist/` |

域名备案、服务类目与平台准入按所选托管商、微信控制台及 [工信部备案系统](https://beian.miit.gov.cn/) 的实际要求核验。域名可以解析，并不代表已经完成应用发布要求。

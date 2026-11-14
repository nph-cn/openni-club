# 零基础：先在自己的电脑跑起来

你不需要先买服务器，也不需要先申请支付。第一次只完成一件事：浏览服务，创建一笔标有「演示」的预约，在订单页看到它，再取消。

## 1. 准备工具

安装 [Node.js 24 LTS](https://nodejs.org/en/download)、[Flutter stable](https://docs.flutter.dev/install)；开发安卓安装 Android Studio，开发苹果需要 macOS 和 Xcode。小程序使用 [微信开发者工具](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)。编辑器可使用 VS Code。

打开终端检查：

```sh
node --version
flutter --version
flutter doctor
```

Node 应为 24.x 或符合项目 API 的最低要求。Flutter 工程通过 `flutter doctor` 确认目标平台工具链。只体验网页版时，可以先处理 Chrome 项，不必等 Android/iOS 全部变绿。

## 2. 打开仓库目录

下载仓库 ZIP 并解压，或用 Git 克隆。终端 `cd` 进入同时包含 `README.md`、`apps`、`services` 的目录；下文称为「仓库根目录」。不要在 ZIP 内直接运行。

复制 `.env.example` 为 `.env`。macOS/Linux：

```sh
cp .env.example .env
```

Windows PowerShell：

```powershell
Copy-Item .env.example .env
```

先保留 `API_MODE=demo`。管理后台需要 `ADMIN_TOKEN`：用密码管理器产生至少 32 字符的随机值，直接填入本地 `.env`，不要发到群聊或提交 Git。不用后台时可以暂留空。

## 3. 启动后端

在根目录运行：

```sh
node scripts/doctor.mjs
node --env-file=.env services/api/src/server.mjs
```

保持这个终端窗口开着。浏览器访问 `http://localhost:8787/health` 应看到 JSON 健康状态。关闭终端会停止本地 API；这不是正式的公网部署。

## 4. 启动 Flutter 预览

打开第二个终端并进入仓库，再运行：

```sh
cd apps/mobile
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8787/api/v1
```

也可不传 `API_BASE_URL` 体验 App 内置演示模式。内置模式的数据仅用于界面预览，不会同步到后端。验证 API 时一定显式传入地址。

## 5. 跑通第一笔演示预约

打开服务列表 → 选择服务 → 查看费用和时长 → 填写未来的预约时间与测试联系方式 → 提交 → 到「订单」查看 → 取消未履约预约。不要填写客户真实个人信息。后端只接受合法状态转换，重复点击应由幂等逻辑防止重复订单。

对照验证：刷新页面后订单是否仍能查看；换一个演示身份后是否无法读取上一身份订单；后台确认后是否按流程显示。注意重新创建演示身份可能得到不同用户，因此不要把清空登录状态当作“数据丢失”。

## 常见错误

| 现象 | 处理 |
| --- | --- |
| 找不到 `node:sqlite` | 检查 `node --version`，使用 Node 24 LTS，避免系统中另一套旧 Node |
| `EADDRINUSE` | 8787 已被占用；停掉你启动的旧实例，或修改 PORT 并同步客户端地址 |
| 浏览器 CORS 错误 | `.env` 的 `CORS_ORIGINS` 加入当前页面完整 origin，例如 `http://localhost:8080`，然后重启 API |
| Android 模拟器连接不上 localhost | 模拟器访问宿主机用 `http://10.0.2.2:8787/api/v1`；仅在开发版本允许明文调试 |
| 手机连接不上电脑 localhost | 手机的 localhost 指手机本身；用同一 Wi-Fi 下电脑局域网 IP 或测试 HTTPS 域名，并按服务端 HOST 配置监听 |
| 小程序模拟器可用，真机失败 | 检查 HTTPS、证书链、合法域名和正式 AppID；开发工具的忽略校验设置不会代替线上配置 |
| 创建订单失败 | 看界面错误信息，检查预约是否为未来时间、联系方式是否完整、API 是否运行；不要把失败提示改成成功 |

继续：[品牌与配置](02-brand-and-config.md)。

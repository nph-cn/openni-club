# 本地启动

本章在自己的电脑上运行 API 和 App，完成一笔测试订单。先使用项目自带的俱乐部资料，不需要服务器或支付账号。

## 1. 安装工具

先安装以下工具，安装完成后再打开终端。

| 工具 | 下载地址 | 用途 |
| --- | --- | --- |
| Node.js 24 LTS | [Node.js 官网](https://nodejs.org/en/download) | 运行 API 和品牌生成脚本 |
| Flutter stable | [Flutter 安装指南](https://docs.flutter.dev/install) | 运行与构建 App |
| Git | [Git 下载](https://git-scm.com/downloads) | 下载、更新项目代码 |
| Chrome | [Chrome 官网](https://www.google.com/chrome/) | 先在浏览器运行 App |

macOS 打开「终端」，Windows 打开「PowerShell」。依次执行：

```sh
node --version
flutter --version
git --version
flutter doctor
```

**检查结果：** Node.js 显示 `v24.x`；Flutter 与 Git 能输出版本；`flutter doctor` 能识别 Chrome。此时只需跑通浏览器，Android Studio、Xcode 和真机工具链可以在发布章节再配置。

如果终端提示“找不到命令”，关闭并重新打开终端再试；仍然失败时，回到对应工具的安装指南检查 PATH。

## 2. 下载并打开项目

在终端进入你存放项目的目录，执行：

```sh
git clone https://github.com/nph-cn/openni-club.git
cd openni-club
npm install
```

也可以在 [GitHub 仓库](https://github.com/nph-cn/openni-club) 点击 **Code → Download ZIP**，解压后在终端进入 `openni-club` 文件夹，再执行 `npm install`。

**检查结果：** 当前文件夹中能看到 `README.md`、`apps`、`services` 和 `package.json`。后文的「仓库根目录」都指这里；不要在 ZIP 压缩包内运行命令。

## 3. 创建本地配置

在仓库根目录复制环境文件。

macOS / Linux：

```sh
cp .env.example .env
```

Windows PowerShell：

```powershell
Copy-Item .env.example .env
```

用编辑器打开 `.env`。第一次运行保留以下配置：

```text
PORT=8787
HOST=127.0.0.1
API_MODE=demo
DATA_DIR=./data
CORS_ORIGINS=http://localhost:4173,http://localhost:8080
```

`demo` 是隔离测试模式，不会创建真实支付。微信和支付字段先留空；需要使用本地运营后台时，再为 `ADMIN_TOKEN` 填写至少 32 字符的随机值。这个文件只保存在自己电脑上，不提交到 Git。

## 4. 启动 API

仍在仓库根目录执行：

```sh
node scripts/doctor.mjs
node --env-file=.env services/api/src/server.mjs
```

保持这个终端窗口打开。在浏览器访问：

```text
http://localhost:8787/health
```

**检查结果：** 浏览器返回 JSON 健康状态，终端没有退出。若提示端口被占用，先停止之前启动的 API，再运行一次。

API 数据保存在仓库的 `data/` 目录。平时更新代码不要删除这个目录。

## 5. 打开 App

打开第二个终端窗口，进入同一个 `openni-club` 文件夹，再执行：

```sh
cd apps/mobile
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8787/api/v1
```

**检查结果：** Chrome 打开 App，能看到俱乐部、服务与成员。保留两个终端窗口：第一个运行 API，第二个运行 Flutter。关闭任意一个，对应服务都会停止。

这里显式传入 `API_BASE_URL`，让 App 连接刚刚启动的 API。省略这个参数会读取内置界面数据，不适合验证服务器订单。

## 6. 提交测试订单

在 App 中按顺序操作：

1. 打开服务列表，选择一项服务和规格。
2. 选择成员，填写未来的预约时间与测试联系方式。
3. 在确认页核对费用、时长和成员，再提交预约。
4. 打开「订单」，查看刚刚提交的记录。
5. 取消一笔尚未履约的测试预约。

**检查结果：** 订单详情显示所选规格、预约时间和状态；返回列表后记录仍可查询。当前环境不发生真实付款，不要输入客户的真实个人信息。

测试完成后，继续 [品牌与资料](02-brand-and-config.md)，换成自己的名称和 Logo。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 找不到 `node:sqlite` | 检查 `node --version`，确认实际运行的是 Node.js 24，而不是系统里的另一套旧版本 |
| `EADDRINUSE` | 8787 已被占用。停止自己启动的旧实例；若修改 `PORT`，也要同步客户端 API 地址 |
| 浏览器提示 CORS 错误 | `.env` 的 `CORS_ORIGINS` 加入当前页面完整来源，例如 `http://localhost:8080`，然后重启 API |
| Android 模拟器连接不上 localhost | 模拟器访问电脑使用 `http://10.0.2.2:8787/api/v1`；明文 HTTP 仅用于开发调试 |
| 手机连接不上电脑 localhost | 手机的 localhost 指手机自身。使用同一 Wi-Fi 下电脑的局域网 IP 或测试 HTTPS 域名，并配置 API 的监听地址 |
| 小程序模拟器可用，真机失败 | 检查 HTTPS、证书、合法域名和自己的 AppID。开发者工具中的忽略校验不能代替线上配置 |
| 创建订单失败 | 按界面的错误提示检查预约时间、联系方式、成员档期和 API 状态 |
| 清除登录后看不到旧订单 | 新的测试身份可能是另一个用户。先核对当前身份，不要直接删除数据库 |

# Hermes 局域网控制台（Hermes LAN Console）

> 在手机上操作本机运行的 [Hermes Agent](https://hermes-agent.nousresearch.com) —— Flutter WebView 壳 App + 零依赖局域网反向代理。

[🌐 切换至英文 / Switch to English](README.en.md)

<p align="center">
  <a href="https://hermes-agent.nousresearch.com"><img src="https://img.shields.io/badge/Hermes_Agent-7C3AED" alt="Hermes Agent"></a>
  <a href="https://github.com/DHJ999/hermes_app/releases"><img src="https://img.shields.io/github/v/release/DHJ999/hermes_app?label=%E7%89%88%E6%9C%AC&color=7C3AED" alt="GitHub 版本"></a>
  <a href="https://github.com/DHJ999/hermes_app/blob/main/LICENSE"><img src="https://img.shields.io/static/v1?label=%E8%AE%B8%E5%8F%AF%E8%AF%81&message=MIT&color=green" alt="MIT 许可证"></a>
  <br>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://nodejs.org"><img src="https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white" alt="Node.js"></a>
  <a href="https://developer.android.com"><img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" alt="Android"></a>
</p>

---

## 🧩 这是什么？

Hermes Agent 的网页控制台（dashboard）默认只监听 `127.0.0.1`，手机直连不到。本仓库提供解决这个问题的两个部件：

| 部件 | 位置 | 作用 |
|---|---|---|
| **pc-bridge** | `pc-bridge/` | 零依赖 Node 反向代理（`server.js`），把本机 dashboard 透传到局域网 `0.0.0.0:8787`；配套一键启动脚本（`start.ps1`）负责起 dashboard、放行防火墙 8787、起反代 |
| **hermes_app** | 仓库根目录 Flutter 工程 | 把 Hermes dashboard 包成接近原生体验的安卓壳 App：可配置地址 + 访问口令、返回键先退网页历史、键盘/滚动适配、强制简体中文、友好的断连页面 |

## 🏗 架构

```
手机（浏览器或壳 App）──WiFi──> 电脑 0.0.0.0:8787 (pc-bridge 反代)
                                    │
                                    └─> 127.0.0.1:9119 (Hermes dashboard 官方界面)
                                            │
                                            └─> 127.0.0.1:4738 (Hermes serve 后端 API, Bearer 令牌)
```

反代把 `Host`/`Origin` 头改写回 loopback，绕过 dashboard 的域名校验。会话令牌每次请求实时透传，**重启 Hermes 后无需改任何配置**。

## 🚀 快速开始

### 🖥️ 1. 电脑端（需管理员——脚本会自动提权来加防火墙规则）

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1
```

带访问口令（推荐，否则同 WiFi 下任何人都能操作你的 Hermes）：

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1 -Token 你的口令
```

脚本会打印局域网地址，例如 `http://192.168.10.4:8787/?token=你的口令`。细节见 `pc-bridge/README.md`。

### 📱 2. 手机端 —— 连同一个 WiFi，二选一

- 浏览器打开打印出的地址，菜单里选「添加到主屏幕」；或
- 安装配套壳 App：

```bash
cd E:\Code\hermes_app
flutter build apk --debug
# APK 在 build\app\outputs\flutter-apk\app-debug.apk
```

App 内点右上角设置，填两项：服务器地址 `http://<电脑局域网IP>:8787`、访问口令（对应 `-Token` 的值；没设口令就留空）。

### 🔧 手动启动（不用 start.ps1）

```powershell
# 1) 起 dashboard（仅本机）
& "C:\Users\duan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m hermes_cli.main dashboard --port 9119 --host 127.0.0.1
# 2) 起反代（另开一个终端）
node E:\Code\hermes_app\pc-bridge\server.js
# 3) 防火墙（一次性）
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=8787 profile=private
```

## ⚙️ 反代配置（环境变量，均可选）

| 变量 | 默认值 | 作用 |
|---|---|---|
| `LISTEN_PORT` | `8787` | 局域网监听端口 |
| `LISTEN_HOST` | `0.0.0.0` | 局域网绑定地址 |
| `TARGET_HOST` / `TARGET_PORT` | `127.0.0.1:9119` | 本机 dashboard 地址 |
| `BRIDGE_TOKEN` | *(空)* | 设置后，未携带令牌（URL `?token=` 或 cookie）的请求一律 `403` |
| `UPSTREAM_TIMEOUT_MS` | `120000` | 上游请求超时 |

反代支持普通 HTTP、SSE 流式、WebSocket 升级。

## 🔒 安全说明

- **仅限局域网 / 同一 WiFi 使用**，不要做公网端口映射。
- 务必设置 `-Token`；未鉴权的局域网访问等于把 Hermes 交到同网段任何人手里。
- 需要**远程**访问时，用 **Tailscale** 组虚拟内网，比暴露端口安全得多。
- 会话令牌只在 loopback 有效；反代改写了 `Host`，外部拿不到令牌直打后端。

## 📚 相关文档

- `pc-bridge/README.md` — 桥接组件详细中文说明（含故障排查）
- `lib/main.dart` — 单文件 Flutter 壳 App 源码
- [🌐 English version](README.en.md)

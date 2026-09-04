# Hermes LAN Console · Hermes 局域网控制台

> Control your [Hermes Agent](https://hermes-agent.nousresearch.com) from your phone — a Flutter WebView shell + a zero-dependency LAN reverse proxy.
> 在手机上操作本机运行的 Hermes Agent —— Flutter WebView 壳 App + 零依赖局域网反向代理。

[English](#english) · [简体中文](#chinese)

---

<a name="english"></a>

## English

### What is this?

Hermes Agent's web dashboard only listens on `127.0.0.1`, so a phone can't reach it directly. This repository ships the two pieces that fix that:

| Piece | Path | What it does |
|---|---|---|
| **pc-bridge** | `pc-bridge/` | Zero-dependency Node reverse proxy (`server.js`) that exposes the local dashboard to the LAN on `0.0.0.0:8787`, plus a one-click launcher (`start.ps1`) that starts the dashboard, opens firewall port 8787 and starts the proxy |
| **hermes_app** | Flutter app in repo root | A WebView shell that wraps the Hermes dashboard into a near-native Android app: configurable address + access token, back-button inside web history, keyboard/scroll fixes, forced Simplified Chinese, a friendly offline page |

### Architecture

```
Phone (browser or shell app) ──WiFi──> PC 0.0.0.0:8787 (pc-bridge reverse proxy)
                                          │
                                          └─> 127.0.0.1:9119 (Hermes dashboard, official UI)
                                                  │
                                                  └─> 127.0.0.1:4738 (Hermes serve backend, Bearer token)
```

The proxy rewrites the `Host`/`Origin` headers back to loopback so the dashboard's domain check is satisfied. Session tokens are passed through live on every request — no config changes needed after restarting Hermes.

### Quick start

**1. On the PC** (run as admin — the script self-elevates for the firewall rule):

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1
```

With an access token (recommended, otherwise anyone on the same WiFi can drive your Hermes):

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1 -Token your-passphrase
```

The script prints the LAN URL, e.g. `http://192.168.10.4:8787/?token=your-passphrase`. See `pc-bridge/README.md` for details.

**2. On the phone** — same WiFi, then either:

- Open the printed URL in a browser and use "Add to Home Screen", or
- Install the companion shell app:

```bash
cd E:\Code\hermes_app
flutter build apk --debug
# APK at build\app\outputs\flutter-apk\app-debug.apk
```

In the app, tap the settings icon and fill in: server address `http://<PC-LAN-IP>:8787` and the access token (leave blank if not set).

### Manual start (without start.ps1)

```powershell
# 1) Start the dashboard (local only)
& "C:\Users\duan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m hermes_cli.main dashboard --port 9119 --host 127.0.0.1
# 2) Start the proxy (another terminal)
node E:\Code\hermes_app\pc-bridge\server.js
# 3) Allow the port through the firewall (once)
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=8787 profile=private
```

### Proxy configuration (env vars, all optional)

| Variable | Default | Purpose |
|---|---|---|
| `LISTEN_PORT` | `8787` | LAN listen port |
| `LISTEN_HOST` | `0.0.0.0` | LAN bind address |
| `TARGET_HOST` / `TARGET_PORT` | `127.0.0.1:9119` | Local dashboard address |
| `BRIDGE_TOKEN` | *(empty)* | If set, requests without the token (URL `?token=` or cookie) get `403` |
| `UPSTREAM_TIMEOUT_MS` | `120000` | Upstream request timeout |

The proxy supports plain HTTP, SSE streaming and WebSocket upgrades.

### Security notes

- **LAN / same-WiFi only.** Don't port-forward it to the public internet.
- Set a `-Token`; unauthenticated LAN access lets anyone control your Hermes.
- For remote access, put the phone and PC on a **Tailscale** mesh instead of exposing a port.
- The session token only works from loopback; the proxy rewrites `Host`, so outsiders can't steal the token to hit the backend directly.

---

<a name="chinese"></a>

## 简体中文

### 这是什么？

Hermes Agent 的网页控制台（dashboard）默认只监听 `127.0.0.1`，手机直连不到。本仓库提供解决这个问题的两个部件：

| 部件 | 位置 | 作用 |
|---|---|---|
| **pc-bridge** | `pc-bridge/` | 零依赖 Node 反向代理（`server.js`），把本机 dashboard 透传到局域网 `0.0.0.0:8787`；配套一键启动脚本（`start.ps1`）负责起 dashboard、放行防火墙 8787、起反代 |
| **hermes_app** | 仓库根目录 Flutter 工程 | 把 Hermes dashboard 包成接近原生体验的安卓壳 App：可配置地址 + 访问口令、返回键先退网页历史、键盘/滚动适配、强制简体中文、友好的断连页面 |

### 架构

```
手机（浏览器或壳 App）──WiFi──> 电脑 0.0.0.0:8787 (pc-bridge 反代)
                                    │
                                    └─> 127.0.0.1:9119 (Hermes dashboard 官方界面)
                                            │
                                            └─> 127.0.0.1:4738 (Hermes serve 后端 API, Bearer 令牌)
```

反代把 `Host`/`Origin` 头改写回 loopback，绕过 dashboard 的域名校验。会话令牌每次请求实时透传，**重启 Hermes 后无需改任何配置**。

### 快速开始

**1. 电脑端**（需管理员——脚本会自动提权来加防火墙规则）：

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1
```

带访问口令（推荐，否则同 WiFi 下任何人都能操作你的 Hermes）：

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1 -Token 你的口令
```

脚本会打印局域网地址，例如 `http://192.168.10.4:8787/?token=你的口令`。细节见 `pc-bridge/README.md`。

**2. 手机端** —— 连**同一个 WiFi**，二选一：

- 浏览器打开打印出的地址，菜单里选「添加到主屏幕」；或
- 安装配套壳 App：

```bash
cd E:\Code\hermes_app
flutter build apk --debug
# APK 在 build\app\outputs\flutter-apk\app-debug.apk
```

App 内点右上角设置，填两项：服务器地址 `http://<电脑局域网IP>:8787`、访问口令（对应 `-Token` 的值；没设口令就留空）。

### 手动启动（不用 start.ps1）

```powershell
# 1) 起 dashboard（仅本机）
& "C:\Users\duan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m hermes_cli.main dashboard --port 9119 --host 127.0.0.1
# 2) 起反代（另开一个终端）
node E:\Code\hermes_app\pc-bridge\server.js
# 3) 防火墙（一次性）
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=8787 profile=private
```

### 反代配置（环境变量，均可选）

| 变量 | 默认值 | 作用 |
|---|---|---|
| `LISTEN_PORT` | `8787` | 局域网监听端口 |
| `LISTEN_HOST` | `0.0.0.0` | 局域网绑定地址 |
| `TARGET_HOST` / `TARGET_PORT` | `127.0.0.1:9119` | 本机 dashboard 地址 |
| `BRIDGE_TOKEN` | *(空)* | 设置后，未携带令牌（URL `?token=` 或 cookie）的请求一律 `403` |
| `UPSTREAM_TIMEOUT_MS` | `120000` | 上游请求超时 |

反代支持普通 HTTP、SSE 流式、WebSocket 升级。

### 安全说明

- **仅限局域网 / 同一 WiFi 使用**，不要做公网端口映射。
- 务必设置 `-Token`；未鉴权的局域网访问等于把 Hermes 交到同网段任何人手里。
- 需要**远程**访问时，用 **Tailscale** 组虚拟内网，比暴露端口安全得多。
- 会话令牌只在 loopback 有效；反代改写了 `Host`，外部拿不到令牌直打后端。

---

## Related docs · 相关文档

- `pc-bridge/README.md` — detailed Chinese guide / 桥接组件详细中文说明（含故障排查）
- `lib/main.dart` — single-file Flutter shell app / 单文件 Flutter 壳 App 源码

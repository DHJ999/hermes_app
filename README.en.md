# Hermes LAN Console

> Control your [Hermes Agent](https://hermes-agent.nousresearch.com) from your phone — a Flutter WebView shell + a zero-dependency LAN reverse proxy.

[🌐 Switch to Chinese / 切换至中文](README.md)

<p align="center">
  <a href="https://hermes-agent.nousresearch.com"><img src="https://img.shields.io/badge/Hermes_Agent-7C3AED" alt="Hermes Agent"></a>
  <a href="https://github.com/DHJ999/hermes_app/releases"><img src="https://img.shields.io/github/v/release/DHJ999/hermes_app?label=Release&color=7C3AED" alt="GitHub Release"></a>
  <a href="https://github.com/DHJ999/hermes_app/blob/main/LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=BUSL-1.1&color=orange" alt="BUSL-1.1, commercial use requires a license"></a>
  <br>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://nodejs.org"><img src="https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white" alt="Node.js"></a>
  <a href="https://developer.android.com"><img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" alt="Android"></a>
</p>

---

## 🧩 What is this?

Hermes Agent's web dashboard only listens on `127.0.0.1`, so a phone can't reach it directly. This repository ships the two pieces that fix that:

| Piece | Path | What it does |
|---|---|---|
| **pc-bridge** | `pc-bridge/` | Zero-dependency Node reverse proxy (`server.js`) that exposes the local dashboard to the LAN on `0.0.0.0:8787`, plus a one-click launcher (`start.ps1`) that starts the dashboard, opens firewall port 8787 and starts the proxy |
| **hermes_app** | Flutter app in repo root | A WebView shell that wraps the Hermes dashboard into a near-native Android app: configurable address + access token, back-button inside web history, keyboard/scroll fixes, forced Simplified Chinese, a friendly offline page |

## 🏗 Architecture

```
Phone (browser or shell app) ──WiFi──> PC 0.0.0.0:8787 (pc-bridge reverse proxy)
                                          │
                                          └─> 127.0.0.1:9119 (Hermes dashboard, official UI)
                                                  │
                                                  └─> 127.0.0.1:4738 (Hermes serve backend, Bearer token)
```

The proxy rewrites the `Host`/`Origin` headers back to loopback so the dashboard's domain check is satisfied. Session tokens are passed through live on every request — no config changes needed after restarting Hermes.

## 🚀 Quick start

### 🖥️ 1. On the PC (run as admin — the script self-elevates for the firewall rule)

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1
```

With an access token (recommended, otherwise anyone on the same WiFi can drive your Hermes):

```powershell
powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1 -Token your-passphrase
```

The script prints the LAN URL, e.g. `http://192.168.10.4:8787/?token=your-passphrase`. See `pc-bridge/README.md` for details.

### 📱 2. On the phone — same WiFi, then either

- Open the printed URL in a browser and use "Add to Home Screen", or
- Install the companion shell app:

```bash
cd E:\Code\hermes_app
flutter build apk --debug
# APK at build\app\outputs\flutter-apk\app-debug.apk
```

In the app, tap the settings icon and fill in: server address `http://<PC-LAN-IP>:8787` and the access token (leave blank if not set).

### 🔧 Manual start (without start.ps1)

```powershell
# 1) Start the dashboard (local only)
& "C:\Users\duan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m hermes_cli.main dashboard --port 9119 --host 127.0.0.1
# 2) Start the proxy (another terminal)
node E:\Code\hermes_app\pc-bridge\server.js
# 3) Allow the port through the firewall (once)
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=8787 profile=private
```

## ⚙️ Proxy configuration (env vars, all optional)

| Variable | Default | Purpose |
|---|---|---|
| `LISTEN_PORT` | `8787` | LAN listen port |
| `LISTEN_HOST` | `0.0.0.0` | LAN bind address |
| `TARGET_HOST` / `TARGET_PORT` | `127.0.0.1:9119` | Local dashboard address |
| `BRIDGE_TOKEN` | *(empty)* | If set, requests without the token (URL `?token=` or cookie) get `403` |
| `UPSTREAM_TIMEOUT_MS` | `120000` | Upstream request timeout |

The proxy supports plain HTTP, SSE streaming and WebSocket upgrades.

## 🔒 Security notes

- **LAN / same-WiFi only.** Don't port-forward it to the public internet.
- Set a `-Token`; unauthenticated LAN access lets anyone control your Hermes.
- For remote access, put the phone and PC on a **Tailscale** mesh instead of exposing a port.
- The session token only works from loopback; the proxy rewrites `Host`, so outsiders can't steal the token to hit the backend directly.

## 📜 License

This project is licensed under the **Business Source License 1.1 (BUSL-1.1)**: everyone may freely view, modify, and use it for **non-commercial** purposes; **any commercial use requires a separate written commercial license from the author (DHJ999)**. On **2030-09-04** the license automatically converts to the Apache License 2.0. See [LICENSE](LICENSE).

## 📚 Related docs

- `pc-bridge/README.md` — detailed Chinese guide for the bridge (incl. troubleshooting)
- `lib/main.dart` — single-file Flutter shell app source
- [🌐 中文版 Chinese version](README.md)

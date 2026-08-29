# Hermes 局域网手机控制台 (hermes-lan-bridge)

把本机运行的 **Hermes 官方网页界面 (dashboard)** 透传到局域网，手机在**同一 WiFi** 下用浏览器即可操作 Hermes。零第三方依赖（仅用 Node 内置模块做反向代理）。

## 为什么这么做
- Hermes 网关 (`hermes_cli.main serve`) 默认只监听 `127.0.0.1`（本机），手机直连不到。
- 直接让 Hermes 监听 `0.0.0.0` 公网绑定会强制要求认证提供方（密码/OAuth）。官方推荐做法就是 **bind 127.0.0.1 + tunnel**。
- 本项目的 `server.js` 就是这台机器上的 "tunnel"：它监听 `0.0.0.0:8787`，把请求转发给本机 `127.0.0.1:9119`（Hermes dashboard），顺带把 `Host`/`Origin` 头改回本机，绕过 dashboard 的域名校验。

## 架构
```
手机浏览器 ──WiFi──> 你的电脑 0.0.0.0:8787 (server.js 反代)
                        │
                        └─> 127.0.0.1:9119 (hermes dashboard, 官方UI)
                                │
                                └─> 127.0.0.1:4738 (hermes serve 后端API, Bearer令牌)
```
会话令牌由 dashboard 根页面动态下发，反代每次都实时透传，**重启 Hermes 后无需改任何配置**。

## 使用步骤
1. 确保 Hermes 桌面端已在运行（它负责后端 serve）。
2. 在本机运行（脚本会自动请求管理员权限用于防火墙放行）：
   ```powershell
   powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1
   ```
   推荐带访问口令（否则同 WiFi 下任何设备都能操作你的 Hermes）：
   ```powershell
   powershell -ExecutionPolicy Bypass -File E:\Code\hermes_app\pc-bridge\start.ps1 -Token 你的口令
   ```
   start.ps1 会自动：启动 Hermes dashboard（首次会现场构建 web UI，约 1~3 分钟）→ 放行防火墙 8787（专用网络）→ 启动反代 → 打印可访问的局域网地址（含口令）。
3. 手机连**同一个 WiFi**，浏览器打开打印出的地址，例如：
   ```
   http://192.168.10.4:8787/?token=你的口令
   ```
   （用你电脑实际拿到、且手机同一网段的那个 IP；不要用 127.0.0.1/localhost）
4. 浏览器菜单「添加到主屏幕 / Add to Home Screen」，即成手机 App。
   或者安装配套的安卓壳 App（见下方「手机壳 App」），体验更接近原生。

## 手机壳 App（hermes_app）
工程在 `E:\Code\hermes_app`（Flutter，WebView 壳 + 地址/口令配置页）。
- 打包：`cd E:\Code\hermes_app && flutter build apk --debug`
  产物在 `build\app\outputs\flutter-apk\app-debug.apk`，传到手机安装即可。
- App 内「设置」填两项：电脑地址 `http://<局域网IP>:8787`、访问口令（对应 start.ps1 -Token 的值；没设口令就留空）。
- 好处：返回键先在网页历史内后退、断连有明确的重试/改配置页、地址变了随时改。

## 手动启动（不用 start.ps1）
```powershell
# 1) 起 dashboard（本机）
& "C:\Users\duan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m hermes_cli.main dashboard --port 9119 --host 127.0.0.1
# 2) 起反代（另开一个终端）
node E:\Code\hermes_app\pc-bridge\server.js
# 3) 防火墙（一次性）
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=8787 profile=private
```

## 配置（环境变量，可选）
- `LISTEN_PORT` 反代监听端口（默认 8787）
- `TARGET_HOST` / `TARGET_PORT` dashboard 地址（默认 127.0.0.1:9119）

## 安全
- 仅限**局域网 / 同一 WiFi** 使用，不要做公网端口映射。
- 会话令牌只在你本机 loopback 有效；反代把 Host 改回本机，外部无法直接拿令牌打后端。
- 若需**远程**（不在家也能用）：装 Tailscale 组虚拟内网，手机走 Tailscale 分配的 IP 访问 `http://<tailscale-ip>:8787`，比暴露端口安全得多。
- 公共/开放 WiFi 下不要用，避免同网段他人蹭到。

## 重启与持久化
- Hermes 重启 / 电脑重启后，需重新运行 start.ps1（dashboard 与反代不会自启）。
- 如需开机自启，可把 start.ps1 放进「任务计划程序」（触发器：登录时，操作：启动 powershell 运行该脚本）。

## 故障排查
- 手机打不开：确认手机和电脑在**同一网段**；电脑防火墙专用网络已放行 8787；电脑本机 `http://127.0.0.1:8787` 能开。
- 400 Bad Request：说明 Host 头没改对（旧版 server.js 才会有），确认用的是带 `buildHeaders` 的版本。
- 白屏：浏览器开发工具看 JS 资源是否 200；多半是 dashboard 还在首次构建中，等几分钟再刷。
- 日志：dashboard 输出在 `hermes-dashboard.out.log` / `.err.log`；反代输出在 `bridge.out.log` / `.err.log`。

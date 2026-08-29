# hermes-lan-bridge 启动脚本 (Windows) v1.1
# 功能：1) 本机启动 Hermes dashboard (127.0.0.1:9119)
#       2) 放行防火墙端口 8787 (专用网络) —— 需要管理员，脚本会自动请求提权
#       3) 启动零依赖反代，把 dashboard 透到局域网 0.0.0.0:8787
# 用法：powershell -ExecutionPolicy Bypass -File start.ps1
#       带令牌：  powershell -ExecutionPolicy Bypass -File start.ps1 -Token 你的口令
# v1.1：自动提权、防重复启动反代、反代日志落盘、dashboard 等待放宽到 300s

param([string]$Token)

$ErrorActionPreference = 'Continue'
$root = "C:\Users\duan\AppData\Local\hermes\hermes-agent"
$cli  = "$root\venv\Scripts\python.exe"
$dashPort = 9119
$bridgePort = 8787
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$out  = Join-Path $here "hermes-dashboard.out.log"
$err  = Join-Path $here "hermes-dashboard.err.log"
$bout = Join-Path $here "bridge.out.log"
$berr = Join-Path $here "bridge.err.log"

function Port-Open($p){
  try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1',$p); $c.Close(); return $true } catch { return $false }
}

# 0) 防火墙规则需要管理员：非管理员时自动请求 UAC 提权重开本脚本
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "[start] 需要管理员权限（防火墙放行），正在请求提权..."
  $scriptPath = Join-Path $here 'start.ps1'
  $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $scriptPath)
  if ($Token) { $argList += @('-Token', $Token) }
  Start-Process powershell -Verb RunAs -ArgumentList $argList
  exit 0
}

# 令牌：命令行参数优先，其次沿用已有环境变量 BRIDGE_TOKEN
if ($Token) { $env:BRIDGE_TOKEN = $Token }

# 1) 启动 dashboard（首次会现场构建 web UI + 下载模型，可能需数分钟）
if (-not (Port-Open $dashPort)) {
  Write-Host "[start] 启动 Hermes dashboard (本机 :$dashPort) ..."
  Start-Process -FilePath $cli -ArgumentList "-m","hermes_cli.main","dashboard","--port",$dashPort,"--host","127.0.0.1" `
    -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
  $t = 0
  while (-not (Port-Open $dashPort) -and $t -lt 300) { Start-Sleep -Seconds 3; $t += 3; Write-Host "[start]   等待 dashboard 起来... ${t}s" }
} else {
  Write-Host "[start] dashboard 已在 :$dashPort 运行"
}

if (-not (Port-Open $dashPort)) { Write-Host "[start] !! dashboard 未起来，查看 $err"; exit 1 }

# 2) 防火墙放行（此处已是管理员）
Write-Host "[start] 放行防火墙 :$bridgePort (专用网络) ..."
netsh advfirewall firewall delete rule name="hermes-lan-bridge" 2>$null | Out-Null
netsh advfirewall firewall add rule name="hermes-lan-bridge" dir=in action=allow protocol=TCP localport=$bridgePort profile=private | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Host "[start]   防火墙规则已添加"
} else {
  Write-Host "[start] !! 防火墙规则添加失败(退出码 $LASTEXITCODE)，手机可能无法访问，请手动放行 :$bridgePort"
}

# 3) 启动反代（已在运行则跳过，避免 EADDRINUSE 静默崩溃）
if (Port-Open $bridgePort) {
  Write-Host "[start] 反代已在 :$bridgePort 运行，跳过启动"
} else {
  Write-Host "[start] 启动局域网反代 :$bridgePort -> 127.0.0.1:$dashPort ..."
  $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
  if (-not $nodeExe) { Write-Host "[start] !! 未找到 node，请确认 Node.js 已安装并在 PATH 中"; exit 1 }
  $serverJs = Join-Path $here 'server.js'
  Start-Process -FilePath $nodeExe -ArgumentList @($serverJs) `
    -RedirectStandardOutput $bout -RedirectStandardError $berr -WindowStyle Hidden
  Start-Sleep -Seconds 2
  if (-not (Port-Open $bridgePort)) { Write-Host "[start] !! 反代未起来，查看 $berr"; exit 1 }
}

# 4) 显示本机局域网 IP，供手机访问
$ips = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|VirtualBox|Docker" -and $_.IPAddress -match "^192\.168\.|^10\.|^172\." }).IPAddress
Write-Host ""
Write-Host "===== 完成 ====="
Write-Host "手机（同一 WiFi）打开以下任一地址即可操作 Hermes："
foreach ($ip in $ips) {
  if ($env:BRIDGE_TOKEN) {
    Write-Host "  http://${ip}:$bridgePort/?token=$($env:BRIDGE_TOKEN)"
  } else {
    Write-Host "  http://${ip}:$bridgePort"
  }
}
if (-not $env:BRIDGE_TOKEN) {
  Write-Host "提示：未启用令牌鉴权，同 WiFi 下任何人都可访问。建议：start.ps1 -Token 你的口令"
}
Write-Host "提示：手机装壳App(hermes_app)时，服务器地址填 http://<上面的IP>:$bridgePort，口令单独填。"

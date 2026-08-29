// hermes-lan-bridge — 零依赖反向代理 (v1.1)
// 作用：把本机 Hermes 官方 dashboard (127.0.0.1:9119) 透传到局域网 0.0.0.0:8787
// 手机连同一个 WiFi，浏览器/壳App 打开 http://<电脑局域网IP>:8787 即可操作 Hermes。
// 支持普通 HTTP、SSE 流式、WebSocket。
//
// v1.1 变更：
//  - 修复 WebSocket 101 握手：必须把 Upgrade/Connection 头写回客户端，否则严格浏览器握手失败
//  - 新增可选令牌鉴权：设置环境变量 BRIDGE_TOKEN 后，未授权访问一律 403
//    首次访问带 ?token=xxx，验证通过写入 cookie，之后所有请求（含 WS 握手）自动携带
//  - 上游请求加超时，防止 dashboard 卡死导致 socket 泄漏
//  - 客户端断开时销毁上游请求
//  - 响应剥离逐跳(hop-by-hop)头，避免 Node writeHead 报错或连接状态错乱
//  - 追加 X-Forwarded-For，dashboard 日志可区分来源
//
// 为什么不直接让 Hermes 监听 0.0.0.0？
//   Hermes 自 v0.20 起，公网绑定强制要求认证提供方（密码/OAuth）。
//   官方推荐做法：bind 127.0.0.1 + tunnel。本代理就是这台机器上的 "tunnel"。

const http = require('http');

const TARGET_HOST = process.env.TARGET_HOST || '127.0.0.1';
const TARGET_PORT = parseInt(process.env.TARGET_PORT || '9119', 10);
const LISTEN_PORT = parseInt(process.env.LISTEN_PORT || '8787', 10);
const LISTEN_HOST = process.env.LISTEN_HOST || '0.0.0.0';
// 为空则不启用鉴权（保持旧行为）；建议局域网也设置一个
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || '';
const COOKIE_NAME = 'hermes_bridge_token';
const UPSTREAM_TIMEOUT_MS = parseInt(process.env.UPSTREAM_TIMEOUT_MS || '120000', 10);

// ---------- 工具 ----------

function parseCookies(req) {
  const out = {};
  const raw = req.headers.cookie;
  if (!raw) return out;
  for (const pair of raw.split(';')) {
    const i = pair.indexOf('=');
    if (i > -1) out[pair.slice(0, i).trim()] = decodeURIComponent(pair.slice(i + 1).trim());
  }
  return out;
}

// 返回 'ok' | 'need-cookie'（URL 带正确 token，需要种 cookie 再跳转）| 'deny'
function checkAuth(req, url) {
  if (!BRIDGE_TOKEN) return 'ok';
  if (url.searchParams.get('token') === BRIDGE_TOKEN) return 'need-cookie';
  if (parseCookies(req)[COOKIE_NAME] === BRIDGE_TOKEN) return 'ok';
  return 'deny';
}

const HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-connection',
  'te', 'trailer', 'transfer-encoding',
]);

function filterResponseHeaders(headers) {
  const out = {};
  for (const k in headers) {
    if (HOP_BY_HOP.has(k.toLowerCase())) continue;
    out[k] = headers[k];
  }
  return out;
}

function buildHeaders(req) {
  const headers = Object.assign({}, req.headers);
  // 把 Host / Origin 改写为本机 loopback，避免 dashboard 拒绝非本机域名 (400)
  headers.host = TARGET_HOST + ':' + TARGET_PORT;
  headers.origin = 'http://' + TARGET_HOST + ':' + TARGET_PORT;
  delete headers['proxy-connection'];
  // 记录真实来源
  const peer = req.socket.remoteAddress || '';
  headers['x-forwarded-for'] = headers['x-forwarded-for']
    ? headers['x-forwarded-for'] + ', ' + peer
    : peer;
  return headers;
}

function deny(res) {
  res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('403 Forbidden：缺少或错误的访问令牌。请在地址后加 ?token=<你的BRIDGE_TOKEN> 访问。');
}

function upstreamOptions(req) {
  return {
    host: TARGET_HOST,
    port: TARGET_PORT,
    path: req.url,
    method: req.method,
    headers: buildHeaders(req),
  };
}

// ---------- 普通 HTTP 转发 ----------

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, 'http://bridge.local');
  } catch (e) {
    res.writeHead(400); res.end('400 Bad Request'); return;
  }

  const auth = checkAuth(req, url);
  if (auth === 'deny') return deny(res);
  if (auth === 'need-cookie') {
    // token 只在首次出现在 URL，验证后种 cookie 并跳干净地址，避免 token 留在历史记录
    url.searchParams.delete('token');
    const rest = url.searchParams.toString();
    res.writeHead(302, {
      location: url.pathname + (rest ? '?' + rest : ''),
      'set-cookie': COOKIE_NAME + '=' + encodeURIComponent(BRIDGE_TOKEN) +
        '; Path=/; Max-Age=31536000; SameSite=Lax',
    });
    res.end();
    return;
  }

  const proxy = http.request(upstreamOptions(req), (upstream) => {
    res.writeHead(upstream.statusCode, filterResponseHeaders(upstream.headers));
    upstream.pipe(res);
  });
  proxy.setTimeout(UPSTREAM_TIMEOUT_MS, () => {
    proxy.destroy(new Error('upstream timeout'));
  });
  proxy.on('error', (e) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('502 Bad Gateway: ' + e.message);
    } else {
      res.destroy();
    }
  });
  // 客户端中途断开 → 销毁上游请求，防泄漏
  res.on('close', () => proxy.destroy());
  req.pipe(proxy);
});

// ---------- WebSocket / 任意协议升级透传 ----------

server.on('upgrade', (req, clientSocket, head) => {
  let url;
  try { url = new URL(req.url, 'http://bridge.local'); }
  catch (e) { clientSocket.destroy(); return; }

  // WS 握手必须已通过 cookie 鉴权（浏览器会自动携带）
  if (BRIDGE_TOKEN && parseCookies(req)[COOKIE_NAME] !== BRIDGE_TOKEN) {
    clientSocket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
    clientSocket.destroy();
    return;
  }

  const proxy = http.request(upstreamOptions(req));
  proxy.setTimeout(UPSTREAM_TIMEOUT_MS, () => proxy.destroy(new Error('upstream timeout')));
  proxy.on('upgrade', (upstream, serverSocket, serverHead) => {
    // 101 响应必须保留 Upgrade/Connection 头（RFC 6455），只去掉 transfer-encoding
    const lines = ['HTTP/1.1 101 Switching Protocols'];
    for (const k in upstream.headers) {
      if (k.toLowerCase() === 'transfer-encoding') continue;
      lines.push(`${k}: ${upstream.headers[k]}`);
    }
    clientSocket.write(lines.join('\r\n') + '\r\n\r\n');
    if (serverHead && serverHead.length) clientSocket.write(serverHead);
    if (head && head.length) serverSocket.write(head);
    serverSocket.pipe(clientSocket);
    clientSocket.pipe(serverSocket);
    serverSocket.on('error', () => clientSocket.destroy());
    clientSocket.on('error', () => serverSocket.destroy());
    clientSocket.on('close', () => serverSocket.destroy());
    serverSocket.on('close', () => clientSocket.destroy());
  });
  proxy.on('error', () => clientSocket.destroy());
  if (head && head.length) proxy.write(head);
  proxy.end();
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(
    `[hermes-lan-bridge] 监听 http://${LISTEN_HOST}:${LISTEN_PORT}  ->  ${TARGET_HOST}:${TARGET_PORT}`
  );
  console.log(
    BRIDGE_TOKEN
      ? '[hermes-lan-bridge] 令牌鉴权：已启用（首次访问需带 ?token=...）'
      : '[hermes-lan-bridge] 令牌鉴权：未启用（建议设置环境变量 BRIDGE_TOKEN）'
  );
  console.log(`[hermes-lan-bridge] 手机访问: http://<本机局域网IP>:${LISTEN_PORT}`);
});

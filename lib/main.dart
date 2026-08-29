import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 默认地址：电脑局域网 IP + 反代端口。手机同一 WiFi 即可访问。
const String defaultUrl = 'http://192.168.10.4:8787';
const String prefsKeyUrl = 'hermes_url';
const String prefsKeyToken = 'hermes_token';

/// 用户没写协议头时自动补 http://
String normalizeUrl(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return u;
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  return 'http://$u';
}

void main() => runApp(const HermesApp());

class HermesApp extends StatelessWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1), // 靛蓝色，更现代
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF818CF8),
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  String _url = defaultUrl;
  String _token = '';
  bool _loading = true;
  bool _loadError = false;
  int _progress = 0;

  /// 早期注入的滚动修复脚本 —— 在页面 DOM 创建时就生效，
  /// 比 Dashboard 自己的 scrollToBottom() 更早执行，从源头禁用平滑滚动。
  static const String _earlyScrollFix = '''
(function() {
  // 1) 强制所有滚动使用 instant 行为
  var style = document.createElement('style');
  style.setAttribute('data-scroll-fix', '1');
  style.textContent = `
    *, *::before, *::after {
      scroll-behavior: auto !important;
    }
    html, body {
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
      touch-action: pan-y !important;
    }
    /* 确保所有可滚动容器都启用触摸滚动 */
    [class*="overflow"] {
      -webkit-overflow-scrolling: touch !important;
      touch-action: pan-y !important;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  // 2) 劫持原生 scrollTo / scrollBy，强制 instant
  var _origScrollTo = Element.prototype.scrollTo;
  var _origScrollBy = Element.prototype.scrollBy;
  var _origScrollIntoView = Element.prototype.scrollIntoView;

  Element.prototype.scrollTo = function(opts) {
    if (typeof opts === 'object') {
      opts = Object.assign({}, opts, { behavior: 'instant' });
    }
    return _origScrollTo.call(this, opts);
  };
  Element.prototype.scrollBy = function(opts) {
    if (typeof opts === 'object') {
      opts = Object.assign({}, opts, { behavior: 'instant' });
    }
    return _origScrollBy.call(this, opts);
  };
  Element.prototype.scrollIntoView = function(opts) {
    if (typeof opts === 'object') {
      opts = Object.assign({}, opts, { behavior: 'instant' });
    } else {
      opts = { behavior: 'instant' };
    }
    return _origScrollIntoView.call(this, opts);
  };

  // 3) 劫持 window.scrollTo / window.scrollBy
  var _winScrollTo = window.scrollTo;
  var _winScrollBy = window.scrollBy;
  window.scrollTo = function() {
    if (window.__keyboardLocked) return; // 键盘弹出期间禁止滚动
    var args = Array.from(arguments);
    if (args.length === 1 && typeof args[0] === 'object') {
      args[0] = Object.assign({}, args[0], { behavior: 'instant' });
    }
    return _winScrollTo.apply(window, args);
  };
  window.scrollBy = function() {
    if (window.__keyboardLocked) return; // 键盘弹出期间禁止滚动
    var args = Array.from(arguments);
    if (args.length === 1 && typeof args[0] === 'object') {
      args[0] = Object.assign({}, args[0], { behavior: 'instant' });
    }
    return _winScrollBy.apply(window, args);
  };

  // 4) 监听 resize 事件，键盘弹出时锁定滚动
  window.addEventListener('resize', function() {
    if (!window.__prevViewportH) window.__prevViewportH = window.innerHeight;
    var diff = window.__prevViewportH - window.innerHeight;
    window.__prevViewportH = window.innerHeight;

    if (diff > 100) {
      // 视口缩小 → 键盘弹出，锁定滚动 500ms
      window.__keyboardLocked = true;
      if (window.__scrollLockTimer) clearTimeout(window.__scrollLockTimer);
      window.__scrollLockTimer = setTimeout(function() {
        window.__keyboardLocked = false;
        window.__scrollLockTimer = null;
      }, 500);
    }
  });
})();
''';

  bool _injected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) {
          setState(() {
            _loading = true;
            _loadError = false;
          });
          _injected = false;
          // 页面开始加载时就注入滚动修复脚本
          _controller.runJavaScript(_earlyScrollFix);
          _injected = true;
        },
        onPageFinished: (_) {
          setState(() => _loading = false);
          _ensureSimplifiedChinese();
          // 确保注入成功（某些情况下 onPageStarted 可能未执行）
          if (!_injected) {
            _controller.runJavaScript(_earlyScrollFix);
            _injected = true;
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) {
            setState(() {
              _loadError = true;
              _loading = false;
            });
          }
        },
      ));
    _loadSavedAndRequest();
  }

  String get _fullUrl {
    final u = normalizeUrl(_url);
    if (_token.isEmpty) return u;
    return u.contains('?')
        ? '$u&token=${Uri.encodeComponent(_token)}'
        : '$u?token=${Uri.encodeComponent(_token)}';
  }

  Future<void> _loadSavedAndRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKeyUrl);
    if (saved != null && saved.isNotEmpty) _url = saved;
    _token = prefs.getString(prefsKeyToken) ?? '';
    _controller.loadRequest(Uri.parse(_fullUrl));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 键盘弹出/收起时，视口高度变化，注入锁定脚本防止页面快速滚动
    _lockScrollOnKeyboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scrollToBottomInstant();
    }
  }

  /// 键盘弹出时锁定滚动，防止快速跳动
  void _lockScrollOnKeyboard() {
    _controller.runJavaScript('''
(function() {
  // 检测视口高度变化（键盘弹出的标志）
  if (!window.__prevViewportH) window.__prevViewportH = window.innerHeight;
  var diff = window.__prevViewportH - window.innerHeight;
  window.__prevViewportH = window.innerHeight;

  // 如果视口缩小超过 100px，说明键盘弹出了
  if (diff > 100) {
    // 记录当前滚动位置，锁定
    window.__keyboardLocked = true;

    // 找到当前滚动的容器，记住它的 scrollTop
    var containers = [
      document.querySelector('[class*="message-list"]'),
      document.querySelector('[class*="chat-scroll"]'),
      document.querySelector('[class*="conversation"]'),
      document.querySelector('main'),
      document.scrollingElement || document.body
    ];
    for (var c of containers) {
      if (c && c.scrollHeight > c.clientHeight) {
        window.__lockedScrollTop = c.scrollTop;
        window.__lockedScrollEl = c;
        break;
      }
    }

    // 拦截所有滚动调用，500ms 内不执行
    if (!window.__scrollLockTimer) {
      window.__origScrollToLocked = window.__origScrollToLocked || Element.prototype.scrollTo;
      Element.prototype.scrollTo = function(opts) {
        if (window.__keyboardLocked) return; // 键盘弹出期间，禁止滚动
        if (typeof opts === 'object') {
          opts = Object.assign({}, opts, { behavior: 'instant' });
        }
        return window.__origScrollToLocked.call(this, opts);
      };

      window.__scrollLockTimer = setTimeout(function() {
        window.__keyboardLocked = false;
        // 键盘动画结束后，平滑地滚到最底部
        var el = window.__lockedScrollEl;
        if (el) {
          window.__origScrollToLocked.call(el, { top: el.scrollHeight, behavior: 'instant' });
        }
        clearTimeout(window.__scrollLockTimer);
        window.__scrollLockTimer = null;
      }, 400);
    }
  }
})();
''');
  }

  /// 无动画滚到底部（息屏恢复时调用）
  void _scrollToBottomInstant() {
    _controller.runJavaScript('''
(function() {
  var selectors = [
    '[class*="message-list"]',
    '[class*="chat-scroll"]',
    '[class*="conversation"]',
    '[data-scroll-container]',
    'main',
    'body'
  ];
  for (var i = 0; i < selectors.length; i++) {
    var el = document.querySelector(selectors[i]);
    if (el && el.scrollHeight > el.clientHeight) {
      el.scrollTop = el.scrollHeight;
      return;
    }
  }
  window.scrollTo(0, document.body.scrollHeight);
})();
''');
  }

  /// 让 Hermes Dashboard 显示简体中文：
  /// 前端把语言存在 localStorage 的 hermes-locale 键（默认强制英文），
  /// 这里检测到不是中文就写入并重载页面，之后每次打开都自动是中文。
  /// 用 _localeFixed 标志防止无限刷新循环。
  bool _localeFixed = false;

  Future<void> _ensureSimplifiedChinese() async {
    if (_localeFixed) return; // 已经处理过，不再重复检查
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        'localStorage.getItem("hermes-locale")',
      );
      // JS 桥会把结果 JSON 编码：字符串带引号（"zh"），null 变成 null
      var lang = raw?.toString().trim() ?? '';
      if (lang.startsWith('"') && lang.endsWith('"') && lang.length >= 2) {
        lang = lang.substring(1, lang.length - 1);
      }
      if (lang != 'zh') {
        _localeFixed = true; // 先置标志，再刷新，防止循环
        await _controller.runJavaScript(
          'localStorage.setItem("hermes-locale", "zh"); '
          'document.documentElement.lang = "zh";',
        );
        _controller.reload();
      } else {
        _localeFixed = true; // 已经是中文，也标记完成
      }
    } catch (_) {
      _localeFixed = true; // 出错也标记，避免反复重试
    }
  }

  void _reload() {
    setState(() {
      _loadError = false;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(_fullUrl));
  }

  Future<void> _editUrl() async {
    final ctrl = TextEditingController(text: _url);
    final tokenCtrl = TextEditingController(text: _token);
    final result = await showDialog<({String url, String token})>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(ctx).colorScheme.primary,
                          Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.link,
                      color: Theme.of(ctx).colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '连接设置',
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: '电脑地址',
                  hintText: 'http://192.168.10.4:8787',
                  helperText: '电脑 ipconfig 查到的、与手机同网段的 IPv4',
                  prefixIcon: const Icon(Icons.computer),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                autofocus: true,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tokenCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '访问口令（可选）',
                  helperText: 'start.ps1 -Token xxx 设置的口令；没设就留空',
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(
                        ctx,
                        (url: ctrl.text.trim(), token: tokenCtrl.text.trim()),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null && result.url.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKeyUrl, result.url);
      await prefs.setString(prefsKeyToken, result.token);
      setState(() {
        _url = result.url;
        _token = result.token;
      });
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // WebView
            WebViewWidget(controller: _controller),

            // 顶部渐变状态栏
            if (_loading || _loadError)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: MediaQuery.of(context).padding.top + 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface.withValues(alpha: 0.95),
                        colorScheme.surface.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

            // 顶部操作栏
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  // 加载进度指示器
                  if (_loading && !_loadError)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              value: _progress == 0 ? null : _progress / 100,
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _progress == 0 ? '连接中...' : '$_progress%',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // 操作按钮
                  if (!_loadError) ...[
                    _ActionButton(
                      icon: Icons.refresh,
                      onTap: _reload,
                      tooltip: '重新连接',
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.settings,
                      onTap: _editUrl,
                      tooltip: '设置地址',
                    ),
                  ],
                ],
              ),
            ),

            // 错误页面
            if (_loadError)
              Container(
                color: colorScheme.surface,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 动画图标
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.errorContainer,
                                colorScheme.errorContainer.withValues(alpha: 0.7),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.error.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.wifi_off_rounded,
                            size: 48,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          '无法连接到 Hermes',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _url,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '请确认电脑已运行 start.ps1，且手机与电脑同一 WiFi',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _editUrl,
                              icon: const Icon(Icons.edit),
                              label: const Text('设置地址'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _reload,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 浮动操作按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

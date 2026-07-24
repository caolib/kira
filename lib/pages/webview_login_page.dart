import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_providers.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/copy_web_login.dart';
import '../utils/toast.dart';

/// 通过应用内 WebView 登录拷贝官网：用户在网页中完成登录后，
/// 从 cookie 中提取 token 并走令牌登录流程。
class WebViewLoginPage extends ConsumerStatefulWidget {
  const WebViewLoginPage({super.key});

  @override
  ConsumerState<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends ConsumerState<WebViewLoginPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _completing = false;
  String? _error;

  String get _host => ref.read(userManagerProvider).copyLoginHost;

  WebUri get _baseUri => WebUri('https://$_host');

  WebUri get _loginUri => WebUri('https://$_host/web/login/loginByAccount');

  /// 读取多个候选域名下的 cookie（官网可能跳转到 www 子域，
  /// token 可能写在父域或当前实际页面域上）。
  Future<Map<String, String>> _readCookieMap() async {
    final manager = CookieManager.instance();
    final result = <String, String>{};
    final candidates = <WebUri>{_baseUri, WebUri('https://www.$_host')};
    final currentUrl = await _controller?.getUrl();
    if (currentUrl != null) candidates.add(currentUrl);

    for (final uri in candidates) {
      try {
        final cookies = await manager.getCookies(url: uri);
        for (final c in cookies) {
          if (c.name.isNotEmpty && !result.containsKey(c.name)) {
            result[c.name] = c.value?.toString() ?? '';
          }
        }
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: st,
            source: 'webview_login.read_cookies',
          ),
        );
      }
    }
    return result;
  }

  static final _tokenPattern = RegExp(r'^[0-9a-fA-F]{32,128}$');
  bool _debugLogged = false;

  /// 从页面存储（document.cookie / localStorage / sessionStorage）中
  /// 提取 token —— h5 版登录可能不写当前域 cookie，而是存 localStorage。
  /// 同时将读到的内容写入应用日志用于诊断。
  Future<String?> _extractTokenFromWebStorage({bool logAlways = false}) async {
    const source = '''
(function(){
  try {
    var ls = {};
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      ls[k] = localStorage.getItem(k);
    }
    var ss = {};
    for (var j = 0; j < sessionStorage.length; j++) {
      var k2 = sessionStorage.key(j);
      ss[k2] = sessionStorage.getItem(k2);
    }
    return JSON.stringify({cookie: document.cookie, ls: ls, ss: ss});
  } catch (e) { return 'error: ' + e; }
})()
''';
    try {
      final raw = await _controller?.evaluateJavascript(source: source);
      final json = raw?.toString();
      if (json == null || json.isEmpty) return null;
      if (logAlways || !_debugLogged) {
        _debugLogged = true;
        unawaited(
          AppLogger.instance.recordWarning(
            'web storage: $json',
            source: 'webview_login.debug',
          ),
        );
      }
      return _findTokenInJson(jsonDecode(json));
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: st,
          source: 'webview_login.web_storage',
        ),
      );
      return null;
    }
  }

  /// 在 JSON 树中递归查找形似 token 的值（32~128 位十六进制串），
  /// localStorage 的值常为嵌套 JSON 字符串，需要逐层解析。
  String? _findTokenInJson(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final value = entry.value;
        if (entry.key == 'token' && value is String && value.isNotEmpty) {
          return value;
        }
        final found = _findTokenInJson(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findTokenInJson(item);
        if (found != null) return found;
      }
    } else if (node is String) {
      if (_tokenPattern.hasMatch(node)) return node;
      if (node.startsWith('{') || node.startsWith('[')) {
        try {
          return _findTokenInJson(jsonDecode(node));
        } catch (_) {
          // 非 JSON 字符串，忽略
        }
      }
    }
    return null;
  }

  Future<void> _tryExtractAndFinish({bool manual = false}) async {
    if (_completing) return;
    final l10n = AppLocalizations.of(context)!;

    Map<String, String> cookieMap;
    try {
      cookieMap = await _readCookieMap();
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: st,
          source: 'webview_login.read_cookies',
        ),
      );
      return;
    }

    var credentials = parseCopyWebCookies(cookieMap);
    if (credentials == null) {
      // cookie 中没有（h5 版可能把 token 存在 localStorage），改从页面存储提取
      final token = await _extractTokenFromWebStorage(logAlways: manual);
      if (token != null) {
        credentials = CopyWebCredentials(
          token: token,
          userId: cookieMap['user_id'] ?? '',
          nickname: '',
          avatar: '',
        );
      }
    }
    if (credentials == null) {
      if (manual && mounted) {
        showToast(context, l10n.profileWebLoginNotDetected);
      }
      return;
    }

    setState(() {
      _completing = true;
      _error = null;
    });

    final user = ref.read(userManagerProvider);
    final api = ref.read(userApiProvider);
    try {
      // 与令牌登录一致：先暂存 token，再用 getUserInfo 验证并补全资料。
      await user.setLoginSource('copy');
      await user.saveLogin(
        token: credentials.token,
        userId: credentials.userId,
        username: '',
        nickname: credentials.nickname,
        avatar: credentials.avatar,
      );
      final info = await api.getUserInfo();
      await user.saveLogin(
        token: credentials.token,
        userId: info['user_id']?.toString() ?? credentials.userId,
        username: info['username']?.toString() ?? '',
        nickname:
            info['nickname']?.toString() ??
            info['username']?.toString() ??
            credentials.nickname,
        avatar: info['avatar']?.toString() ?? credentials.avatar,
      );
      if (mounted) context.pop(true);
    } catch (e) {
      await user.logout();
      if (mounted) {
        setState(() {
          _completing = false;
          _error = '${l10n.profileWebLoginFailed}\n$e';
        });
      }
    }
  }

  Future<void> _resetWebSession() async {
    final manager = CookieManager.instance();
    await manager.deleteCookies(url: _baseUri, domain: '.$_host');
    await manager.deleteCookies(url: _baseUri, domain: _host);
    await _controller?.loadUrl(urlRequest: URLRequest(url: _loginUri));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileWebLoginPageTitle),
        actions: [
          IconButton(
            tooltip: l10n.profileWebLoginResetTooltip,
            onPressed: _completing ? null : _resetWebSession,
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: _completing
                ? null
                : () => _tryExtractAndFinish(manual: true),
            child: Text(l10n.profileWebLoginManualButton),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_progress < 1)
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
              Container(
                width: double.infinity,
                color: cs.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  l10n.profileWebLoginHint,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  color: cs.errorContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    _error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
                  ),
                ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: _loginUri),
                  onWebViewCreated: (controller) => _controller = controller,
                  onProgressChanged: (controller, progress) {
                    setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (controller, url) => _tryExtractAndFinish(),
                  onUpdateVisitedHistory: (controller, url, isReload) =>
                      _tryExtractAndFinish(),
                ),
              ),
            ],
          ),
          if (_completing)
            Positioned.fill(
              child: ColoredBox(
                color: cs.scrim.withValues(alpha: 0.4),
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacing.lg),
                          Text(l10n.profileWebLoginCompleting),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

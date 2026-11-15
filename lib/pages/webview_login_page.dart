import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../models/copy_account_store.dart';
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/copy_web_login.dart';
import '../utils/network_error.dart';

/// 官网登录凭据抓取脚本。
///
/// 密码由网页直接 POST 给服务器，客户端拿不到表单体，所以在页面里挂钩网络
/// 层，从真实的登录请求里解出账号密码，通过 `copyLoginForm` 桥回 Flutter。
///
/// 依据（取自官网静态资源，非猜测）：
/// - 页面是 Vue + Element UI（桌面站）或 Vant（h5 站），都使用 **axios** 且
///   通过 `XMLHttpRequest` 发包；
/// - 登录接口见 [copyLoginSubmitPaths]，表单体为
///   `username=<账号>&password=<base64(密码-salt)>&salt=<随机>&platform=…`；
/// - 密码框默认明文（源码 `visiablePassword: true`），DOM 上没有 type=password，
///   所以不靠 DOM 结构识别。
///
/// 只有从真实网络请求里解出的凭据才会回报，因此不存在「把没提交的输入框内容
/// 当登录」的问题。官网改版导致钩子失效时脚本静默退出（只是不再保存密码），
/// 不影响登录本身。
final _loginFormScript = buildCopyLoginFormScript();

/// 官网登录凭据抓包脚本（见上方说明）。独立成公开函数便于离线测试。
String buildCopyLoginFormScript() =>
    r'''
(function () {
  if (window.__copyLoginProbe) return;
  window.__copyLoginProbe = true;

  // 自动填表脚本每次导航都会重新注入，同一账号可能被提交两次（自动填表先点
  // 了一次、用户随后又手点一次）。解除上报去重，让第二次提交也能被看到。
  window.__copyLoginProbeReset = function () {
    window.__copyLoginReported = null;
  };

  function report(username, password) {
    if (!username || !password) return;
    if (window.__copyLoginReported === username + '\n' + password) return;
    window.__copyLoginReported = username + '\n' + password;
    try {
      window.flutter_inappwebview.callHandler(
        'copyLoginForm', username, password, true
      );
    } catch (e) {}
  }

  // 只认登录接口，避免把注册/找回密码的请求当成登录。
  var loginPaths = ''' +
    jsonEncode(copyLoginSubmitPaths) +
    r''';

  function isLoginUrl(url) {
    if (!url) return false;
    var s = String(url);
    for (var i = 0; i < loginPaths.length; i++) {
      if (s.indexOf(loginPaths[i]) >= 0) return true;
    }
    return false;
  }

  function decodeBody(body) {
    if (!body || typeof body !== 'string') return null;
    var username = '';
    var password = '';
    var salt = '';
    var pairs = body.split('&');
    for (var i = 0; i < pairs.length; i++) {
      var idx = pairs[i].indexOf('=');
      if (idx < 0) continue;
      var key = pairs[i].slice(0, idx);
      var value = pairs[i].slice(idx + 1);
      try { value = decodeURIComponent(value.replace(/\+/g, ' ')); } catch (e) {}
      if (key === 'username') username = value;
      else if (key === 'password') password = value;
      else if (key === 'salt') salt = value;
    }
    if (!username || !password) return null;
    var decoded = '';
    try {
      // 官网把密码编码成 base64(密码 + '-' + salt)，解回来才是明文。
      decoded = atob(password);
      if (salt) {
        var suffix = '-' + salt;
        if (decoded.slice(-suffix.length) === suffix) {
          decoded = decoded.slice(0, decoded.length - suffix.length);
        }
      }
    } catch (e) {
      return null;
    }
    if (!decoded) return null;
    return { username: username.trim(), password: decoded };
  }

  function inspect(method, url, body) {
    try {
      if (!isLoginUrl(url)) return;
      if (method && String(method).toUpperCase() !== 'POST') return;
      var parsed = decodeBody(body);
      if (parsed) report(parsed.username, parsed.password);
    } catch (e) {}
  }

  // axios 在浏览器里走 XMLHttpRequest；钩住 send/open 就能拿到登录表单体。
  var send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body) {
    inspect(this.__copyLoginMethod, this.__copyLoginUrl, body);
    return send.apply(this, arguments);
  };
  var open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__copyLoginMethod = method;
    this.__copyLoginUrl = url;
    return open.apply(this, arguments);
  };

  // 少数情况下页面可能改用 fetch，一并兜底。
  if (typeof window.fetch === 'function') {
    var rawFetch = window.fetch;
    window.fetch = function (input, init) {
      try {
        var url = input && input.url ? input.url : input;
        inspect(init && init.method ? init.method : 'GET', url, init && init.body);
      } catch (e) {}
      return rawFetch.apply(this, arguments);
    };
  }
})();
''';

/// 官网登录页自动填表脚本（桌面版 Element UI 与移动版 Vant 双结构兼容）。
///
/// 把传入的账号密码填进登录表单并触发登录按钮，账号密码以 JSON 对象字面量
/// 内嵌，不存在字符串转义/注入问题。结构依据（均取自官网真实页面）：
/// - 桌面版 `/web/login/loginByAccount`：`form.el-form`（登录 tab 默认激活）
///   内 `.el-input__inner` 依次是账号与密码，登录按钮是可见 pane 里唯一的
///   `button.el-button--primary`（注册 pane 里也有 display:none 的 primary，
///   用 offsetParent 过滤）；
/// - 移动版 `/h5/login`：`form.van-form` 内 `.van-field__control` 依次是
///   账号与密码，登录按钮是 `button.van-button-login`（注册按钮带
///   `--plain`，不会混淆）。
///
/// 两者都是 Vue（Element UI / Vant）+ v-model，需要 native setter + input
/// 事件才能让框架感知输入。
///
/// 脚本**可重复注入**：官网 h5 站是 history 路由 SPA，首次进入会被强制送到
/// 线路选择页 `/h5/init`，用户选完线路才 `replace` 回 `/h5/login`（不重新加载
/// 文档），所以要等登录表单真的出现才注入；而表单可能比 8 秒更晚出现，单次
/// 注入超时后就没机会了。因此每次调用都重置脚本状态并重新计时，只有表单已经
/// 填过、且仍在等待结果时才跳过（[skipFilled]）。登录被拒时通过 `copyAutoLogin`
/// 桥回报错误文案（Element 的 `.el-message--error` 与 Vant 的 `.van-toast`，
/// 后者无法从 class 区分类型，靠「成功」字样过滤）。
String buildCopyLoginFillScript({
  required String username,
  required String password,
  bool skipFilled = false,
}) {
  final payload = jsonEncode({'username': username, 'password': password});
  final skipFilledLiteral = skipFilled ? 'true' : 'false';
  return '''
(function () {
  var skipFilled = $skipFilledLiteral;
  var filled = window.__copyAutoLoginFilled;
  if (filled) {
    // 已填过：默认不重复点击（用户可能正在改密码），仍在等结果时也不重复。
    if (!skipFilled) return;
    if (window.__copyAutoLoginPending) return;
    window.__copyAutoLoginPending = true;
  }
  window.__copyAutoLoginInjected = true;

  // 每次注入都从干净状态开始，用户选完线路回到登录页后能重新识别表单。
  if (window.__copyAutoLoginTimer) clearInterval(window.__copyAutoLoginTimer);
  if (window.__copyAutoLoginObserver) window.__copyAutoLoginObserver.disconnect();
  if (window.__copyLoginProbeReset) window.__copyLoginProbeReset();
  window.__copyAutoLoginFilled = false;

  var params = $payload;

  function report(event, detail) {
    try {
      window.flutter_inappwebview.callHandler('copyAutoLogin', event, detail || '');
    } catch (e) {}
  }

  var reported = false;
  function finish(event, detail) {
    if (reported) return;
    reported = true;
    window.__copyAutoLoginPending = false;
    report(event, detail);
  }

  function setValue(input, value) {
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function findTargets() {
    // 桌面版（Element UI）。
    var form = document.querySelector('form.el-form');
    if (form) {
      var inputs = form.querySelectorAll('.el-input__inner');
      var buttons = document.querySelectorAll('button.el-button--primary');
      var button = null;
      for (var i = 0; i < buttons.length; i++) {
        if (buttons[i].offsetParent !== null) { button = buttons[i]; break; }
      }
      if (inputs.length >= 2 && button) {
        return { username: inputs[0], password: inputs[1], button: button };
      }
    }
    // 移动版（Vant UI h5）。
    var vform = document.querySelector('form.van-form');
    if (vform) {
      var vinputs = vform.querySelectorAll('.van-field__control');
      var vbutton =
        vform.querySelector('.van-button-login') ||
        document.querySelector('button.van-button--danger:not(.van-button--plain)');
      if (vinputs.length >= 2 && vbutton) {
        return { username: vinputs[0], password: vinputs[1], button: vbutton };
      }
    }
    return null;
  }

  function watchErrors() {
    if (!window.MutationObserver || !document.body) return;
    var observer = new MutationObserver(function () {
      var messages = document.querySelectorAll('.el-message--error, .van-toast');
      for (var i = 0; i < messages.length; i++) {
        var el = messages[i];
        var cls = el.className || '';
        if (cls.indexOf('--success') >= 0) continue;
        var body = el.querySelector('.van-toast__text') || el;
        var text = body.textContent.trim();
        if (!text) continue;
        // 加载中 toast 与成功 toast 都不是登录结果，只报真正的失败提示。
        if (/加[载載]|載入|loading|稍[後后]/i.test(text)) continue;
        if (/成功|success/i.test(text)) continue;
        finish('error', text);
        observer.disconnect();
        return;
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
    window.__copyAutoLoginObserver = observer;
    // 登录结果只会出现在提交后的短时间内，之后停止观察。
    setTimeout(function () { observer.disconnect(); }, 15000);
  }

  function checkFieldErrors() {
    var errors = document.querySelectorAll('.el-form-item__error, .van-field__error-message');
    if (errors.length > 0) {
      finish('error', errors[0].textContent.trim());
    }
  }

  var attempts = 0;
  window.__copyAutoLoginTimer = setInterval(function () {
    attempts++;
    var targets = findTargets();
    if (targets) {
      clearInterval(window.__copyAutoLoginTimer);
      window.__copyAutoLoginTimer = null;
      window.__copyAutoLoginFilled = true;
      window.__copyAutoLoginPending = true;
      setValue(targets.username, params.username);
      setValue(targets.password, params.password);
      targets.button.click();
      watchErrors();
      setTimeout(function () { checkFieldErrors(); }, 2000);
    } else if (attempts * 300 >= 30000) {
      clearInterval(window.__copyAutoLoginTimer);
      window.__copyAutoLoginTimer = null;
      window.__copyAutoLoginPending = false;
      finish('form_not_found', '');
    }
  }, 300);
})();
''';
}

/// 清空 WebView 里残留的登录态，让本次登录从全新环境开始。
///
/// 官网的登录态是持久的：cookie 与 localStorage 都会跨会话保留，上次登录
/// 的痕迹会干扰本次登录（例如页面带着旧 token 直接跳登录后首页、自动填表
/// 提交被旧会话顶掉）。所以在加载登录页之前先清一次。
///
/// 各平台能力不同（依据 flutter_inappwebview 官方文档与插件源码）：
/// - Android：`deleteAllData()` 清 Web Storage，`deleteAllCookies()` 清 cookie；
/// - iOS / macOS：没有 `deleteAllData()`，要用 `fetchDataRecords()` 找到记录后
///   `removeDataFor()` 删除；`deleteAllCookies()` 内部同样是按 cookies 类型删；
/// - Windows：插件只实现了 cookie 管理，没有 Web Storage 原生实现，
///   清不到 localStorage（登录页本身仍可用，只是 h5 站残留会留着）；
/// - Linux / Web：插件没有对应实现，直接跳过。
///
/// 清理失败不阻断登录：登录流程本身有「本次是否真的提交过登录」的判定
/// （[_WebViewLoginPageState._submittedLogin]），清不掉也不会误登旧账号。
Future<void> clearWebViewLoginState() async {
  if (kIsWeb) return;
  try {
    await CookieManager.instance().deleteAllCookies();
  } catch (error, st) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: st,
        source: 'webview_login.clear_cookies',
      ),
    );
  }
  try {
    final storage = WebStorageManager.instance();
    if (Platform.isAndroid) {
      await storage.deleteAllData();
    } else if (Platform.isIOS || Platform.isMacOS) {
      final records = await storage.fetchDataRecords(
        dataTypes: WebsiteDataType.values,
      );
      await storage.removeDataFor(
        dataTypes: WebsiteDataType.values,
        dataRecords: records,
      );
    }
  } catch (error, st) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: st,
        source: 'webview_login.clear_storage',
      ),
    );
  }
}

/// 通过应用内 WebView 登录拷贝官网。
///
/// 用户在 kira 登录页填好账号密码后进入本页，脚本自动填表并触发表单提交，
/// 网页自己发出登录请求；登录成功后从 cookie/storage 提取 token，走令牌
/// 登录落库。进入页面时会先清空 WebView 残留的登录态（见
/// [clearWebViewLoginState]），保证每次登录都是全新环境。
class WebViewLoginPage extends ConsumerStatefulWidget {
  const WebViewLoginPage({super.key, required this.autoFill});

  /// 登录页填好的账号密码；页面加载完成后自动填表并触发表单提交，
  /// 失败时用户仍可在网页里手动改密码重试。
  final ({String username, String password}) autoFill;

  @override
  ConsumerState<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends ConsumerState<WebViewLoginPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _completing = false;
  bool _readingCredentials = false;
  String? _error;

  /// 本次会话里钩到过真实的官网登录提交（见 [_loginFormScript]）。只有它
  /// 能证明提取到的登录态是用户刚刚登录的结果，而不是进入页面前残留的
  /// 旧会话。
  bool _submittedLogin = false;

  /// 自动填表提交后被官网明确拒绝（错误提示条）。此时不再自动重填，把页面
  /// 留给用户改密码，避免在页面导航时反复提交同一个错误密码。
  bool _autoFillRejected = false;

  /// 表单抓取到的密码，按用户名暂存，登录完成时一并落到对应账号上。
  final _loginFormPasswords = <String, String>{};

  /// 自动填表提交后的 cookie 轮询：登录是 axios 请求、不一定触发页面导航，
  /// 靠轮询保证拿到新 token。
  Timer? _autoFillPoll;

  /// 清空残留登录态的异步任务。WebView 要等它完成后才创建，否则清理与页面
  /// 加载会互相竞争（清掉的 cookie 可能又被加载中的页面写回来）。
  late final Future<void> _cleared = clearWebViewLoginState();

  @override
  void dispose() {
    _autoFillPoll?.cancel();
    super.dispose();
  }

  String get _host => ref.read(userManagerProvider).copyLoginHost;

  /// 官网按 UA 分流：移动 WebView（Android/iOS）会被重定向到 Vant 版 h5
  /// 站点，登录页是 `/h5/login`；桌面 WebView2 的登录页才是
  /// `/web/login/loginByAccount`。
  bool get _isMobileSite => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  WebUri get _loginUri => WebUri(
    'https://$_host${_isMobileSite ? '/h5/login' : '/web/login/loginByAccount'}',
  );

  /// 脚本只在拷贝官网自己的页面上执行，避免把凭证交给其它站点。
  Set<String> get _scriptOriginRules {
    final base = _host.startsWith('www.') ? _host.substring(4) : _host;
    return {'https://$base', 'https://www.$base'};
  }

  /// 脚本只在用户真正提交表单后上报，因此这里可以放心暂存密码；用户名与
  /// 已保存账号对不上时不写入。
  void _onLoginFormReported(List<dynamic> arguments) {
    if (arguments.length < 3) return;
    final username = arguments[0]?.toString().trim() ?? '';
    final password = arguments[1]?.toString() ?? '';
    if (arguments[2] != true) return;
    if (username.isEmpty || password.isEmpty) return;
    _loginFormPasswords[username] = password;
    _submittedLogin = true;
  }

  /// 自动填表提交后轮询 cookie；页面跳转（onUpdateVisitedHistory/onLoadStop）
  /// 会先一步完成登录，轮询只是兜底。提示条出现时轮询继续：自动填表可能随后
  /// 把会话换成另一个账号，后续提取会覆盖提示条。
  ///
  /// 窗口按「h5 站的登录请求是 XHR、成功后不跳路由」放宽：单次提取可能早于
  /// cookie/localStorage 写入，必须留够重试时间（官网配置的请求超时是 10 秒）。
  void _startCredentialPoll() {
    _autoFillPoll?.cancel();
    var tries = 0;
    _autoFillPoll = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _completing) {
        timer.cancel();
        return;
      }
      if (++tries > 80) {
        timer.cancel();
        return;
      }
      _tryExtractAndFinish();
    });
  }

  /// 自动填表脚本的桥回报：`error` 展示到顶部错误条，其余事件静默。
  void _onAutoLoginEvent(List<dynamic> arguments) {
    if (arguments.isEmpty || arguments.first is! String) return;
    if (arguments.first as String != 'error') return;
    _autoFillRejected = true;
    final detail = arguments.length > 1 ? (arguments[1]?.toString() ?? '') : '';
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final trimmed = detail.trim();
    setState(() {
      _error = trimmed.isEmpty
          ? l10n.profileWebLoginFailed
          : l10n.profileCopyAutoLoginRejected(trimmed);
    });
  }

  /// 自动填表：只要当前地址是官网登录页就（重新）注入脚本，交由网页自己提交
  /// 登录。
  ///
  /// h5 站是 history 路由 SPA：首次进入会被强制送到线路选择页 `/h5/init`，
  /// 用户选完线路才 `replace` 回 `/h5/login`（不重新加载文档）。所以既要在
  /// `onLoadStop` 注入，也要在 `onUpdateVisitedHistory`（SPA 导航）注入；脚本
  /// 自身负责「表单已填过就不重复点、找不到表单就继续等」。
  Future<void> _injectAutoFill(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    final fill = widget.autoFill;
    // 已被官网拒绝时不再自动重填，把页面留给用户改密码重试。
    if (_autoFillRejected && _submittedLogin) return;
    final path = url?.toString() ?? '';
    final isLoginPage =
        path.contains('/web/login/loginByAccount') ||
        path.contains('/h5/login');
    if (!isLoginPage) return;
    try {
      await controller.evaluateJavascript(
        source: buildCopyLoginFillScript(
          username: fill.username,
          password: fill.password,
          // 用户手动改密码重试时，已填过也要重新填一遍新密码。
          skipFilled: _submittedLogin,
        ),
      );
      _startCredentialPoll();
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to inject COPY login autofill',
          stackTrace: st,
          source: 'webview_login.autofill',
        ),
      );
    }
  }

  /// 登录成功后把暂存的密码并回本机凭据，供令牌失效后的自动重登使用。
  Future<void> _persistLoginFormPasswords(UserManager user) async {
    if (_loginFormPasswords.isEmpty) return;
    final pending = Map<String, String>.from(_loginFormPasswords);
    _loginFormPasswords.clear();
    // 一次成功的提交就足以锚定账号；清掉钩子侧的去重，让用户改密码后的
    // 下一次提交也能被看到。
    _autoFillRejected = false;
    try {
      await _controller?.evaluateJavascript(
        source:
            'window.__copyLoginProbeReset && window.__copyLoginProbeReset();',
      );
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to reset COPY login probe',
          stackTrace: st,
          source: 'webview_login.reset_probe',
        ),
      );
    }
    await user.saveLoginFormPasswords(pending);
  }

  /// Read each official host separately; cookie fields from different hosts
  /// must never be assembled into one account.
  Future<CopyWebCredentials?> _readCookieCredentials() async {
    final manager = CookieManager.instance();
    final currentUrl = await _controller?.getUrl();
    final base = _host.startsWith('www.') ? _host.substring(4) : _host;
    final candidates = <WebUri>{
      if (currentUrl != null && _isLoginHost(currentUrl.host)) currentUrl,
      WebUri('https://$_host'),
      WebUri('https://$base'),
      WebUri('https://www.$base'),
    };

    for (final uri in candidates) {
      try {
        final cookies = await manager.getCookies(url: uri);
        final values = <String, String>{};
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty) {
            values.putIfAbsent(
              cookie.name,
              () => cookie.value?.toString() ?? '',
            );
          }
        }
        final credentials = parseCopyWebCookies(values);
        if (credentials != null) return credentials;
      } catch (_, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Unable to read COPY WebView cookies',
            stackTrace: st,
            source: 'webview_login.read_cookies',
          ),
        );
      }
    }
    return null;
  }

  bool _isLoginHost(String host) {
    final base = _host.startsWith('www.') ? _host.substring(4) : _host;
    return host == base || host == 'www.$base';
  }

  /// Read the official page's candidate token and profile together. Storage
  /// from a navigation to another website must never be submitted as COPY.
  Future<CopyWebCredentials?> _extractCredentialsFromWebStorage({
    String? matchingToken,
  }) async {
    final currentUrl = await _controller?.getUrl();
    if (currentUrl == null || !_isLoginHost(currentUrl.host)) return null;
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
    return JSON.stringify({ls: ls, ss: ss});
  } catch (e) { return 'error: ' + e; }
})()
''';
    try {
      final raw = await _controller?.evaluateJavascript(source: source);
      final json = raw?.toString();
      if (json == null || json.isEmpty) return null;
      final pageUrl = await _controller?.getUrl();
      if (pageUrl == null || !_isLoginHost(pageUrl.host)) return null;
      return parseCopyWebStorage(
        jsonDecode(json),
        matchingToken: matchingToken,
      );
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to read COPY WebView storage',
          stackTrace: st,
          source: 'webview_login.web_storage',
        ),
      );
      return null;
    }
  }

  Future<void> _tryExtractAndFinish() async {
    if (_completing || _readingCredentials) return;

    _readingCredentials = true;
    CopyWebCredentials? credentials;
    try {
      credentials = await _readCookieCredentials();
      final stored = await _extractCredentialsFromWebStorage(
        matchingToken: credentials?.token,
      );
      if (stored != null &&
          (credentials == null ||
              (stored.token == credentials.token &&
                  stored.profileBoundToToken))) {
        credentials = stored;
      }
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to read COPY WebView credentials',
          stackTrace: st,
          source: 'webview_login.read_credentials',
        ),
      );
    } finally {
      _readingCredentials = false;
    }
    if (!mounted) return;
    // 页面一打开就可能带着上次的官网会话。只有本次真的提交过登录，才能
    // 认定提取到的是用户刚登录的账号；否则一律不动，免得把已登出/已删除的
    // 账号在用户输入新账号前抢登回来。
    if (credentials == null || !_submittedLogin) return;
    await _completeLogin(credentials);
  }

  Future<void> _completeLogin(CopyWebCredentials credentials) async {
    if (_completing) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _completing = true;
      _error = null;
    });

    final user = ref.read(userManagerProvider);
    final api = ref.read(userApiProvider);
    try {
      final saved = await completeCopyWebLogin(
        user: user,
        api: api,
        credentials: credentials,
        persistLoginFormPasswords: () async {
          if (!mounted) return;
          // 登录已成功；先补回表单密码，再用最终账号 revision 刷新资料。
          await _persistLoginFormPasswords(user);
          // 移动版 h5 的表单体不一定可解析，以本次登录 token 锚定自动填表密码。
          final fill = widget.autoFill;
          await user.saveLoginFormPasswords({
            fill.username: fill.password,
          }, anchorToken: credentials.token);
        },
      );
      if (!mounted) return;
      if (saved) {
        context.pop(true);
      } else {
        setState(() {
          _completing = false;
          _error = l10n.copyAccountLoginSuperseded;
        });
      }
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'webview_login.validate',
        ),
      );
      if (mounted) {
        setState(() {
          _completing = false;
          _error = error is CopyAccountStorageException
              ? l10n.copyAccountStorageFailed
              : NetworkError.message(error, l10n: l10n);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileWebLoginPageTitle)),
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
                color: cs.surfaceBright,
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
                // 等残留登录态清干净再建 WebView：边清边加载会让页面把清掉的
                // cookie 又写回来，等于没清。
                child: FutureBuilder<void>(
                  future: _cleared,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildWebView();
                  },
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

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: _loginUri),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: _loginFormScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          allowedOriginRules: _scriptOriginRules,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'copyLoginForm',
          callback: _onLoginFormReported,
        );
        controller.addJavaScriptHandler(
          handlerName: 'copyAutoLogin',
          callback: _onAutoLoginEvent,
        );
      },
      onProgressChanged: (controller, progress) {
        setState(() => _progress = progress / 100);
      },
      onLoadStop: (controller, url) {
        _tryExtractAndFinish();
        _injectAutoFill(controller, url);
      },
      // h5 站登录成功后只写 cookie/localStorage、不跳路由，此时只能靠上面的
      // 轮询；这里覆盖桌面站的整页跳转，以及用户手动改完密码后 h5 站可能发生
      // 的 SPA 导航（顺带重新注入脚本）。
      onUpdateVisitedHistory: (controller, url, isReload) {
        _tryExtractAndFinish();
        _injectAutoFill(controller, url);
      },
    );
  }
}

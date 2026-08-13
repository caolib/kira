import 'package:shared_preferences/shared_preferences.dart';

/// 构造与解析 kira:// 自定义协议深链。
///
/// 链接格式：`kira://open{内部路由路径}`——host 固定为 `open`，path 部分
/// 与 GoRouter 声明的路由一致，因此深链可直接交给 GoRouter 匹配，无需
/// 额外的重定向代码。例如 `kira://open/comic/xxx` 会打开漫画详情页
/// `/comic/:pathWord`。
///
/// 接收侧由 AndroidManifest 中 MainActivity 的 `kira` scheme
/// intent-filter 交付给 Flutter，详见 [KiraLinks.scheme]。
abstract final class KiraLinks {
  /// 自定义协议 scheme，AndroidManifest intent-filter 需与此保持一致。
  static const scheme = 'kira';

  /// 分享落地页域名(kira 官网,部署在 Cloudflare Pages)。
  ///
  /// ⚠️ 该域名必须与官网实际部署域名一致——修改时同步三处:
  /// 这里、`AndroidManifest.xml` 的 https intent-filter host、
  /// 以及 kira-web 仓库部署(含 `/.well-known/assetlinks.json`,
  /// 部署后可在 intent-filter 上加 `android:autoVerify="true"` 免确认直达)。
  static const webHost = 'kirakira.dpdns.org';

  /// 漫画详情深链:`kira://open/comic/{pathWord}`(App 内路由直达)。
  static String comicDetail(String pathWord) =>
      Uri(scheme: scheme, host: 'open', path: '/comic/$pathWord').toString();

  /// 漫画详情 https 分享链接:`https://{webHost}/c/?w={pathWord}`。
  ///
  /// 任何 App/浏览器都能点开:装有 kira 的设备由 https intent-filter 直接
  /// 拉起(App Link),否则打开官网落地页,由页面自动跳转 kira:// 深链或
  /// 引导下载。故意用「静态页 + 查询参数」而非路径重写——CF Pages 对 SPA
  /// 项目的扩展名less 路径默认回落 index.html,会抢在 _redirects 重写之前。
  static String comicShareUrl(String pathWord) => Uri(
    scheme: 'https',
    host: webHost,
    path: '/c/',
    queryParameters: {'w': pathWord},
  ).toString();

  /// 匹配文本中的漫画分享链接(https 分享链接或 kira:// 深链)。
  /// pathWord 只含字母、数字、下划线与连字符,因此链接后紧跟空白或
  /// 中文标点(如「。」)时也能正确截断。
  static final _comicLinkPattern = RegExp(
    '(?:$scheme://open/comic/|https://${RegExp.escape(webHost)}/c/\\?w=)'
    '([\\w-]+)',
  );

  /// 从任意文本（如剪贴板内容）中提取漫画分享链接的 pathWord，没有则返回 null。
  static String? extractComicPathWord(String text) =>
      _comicLinkPattern.firstMatch(text)?.group(1);

  static final _pathWordPattern = RegExp(r'^[\w-]+$');

  /// 把接收到的 https 分享链接 URI 映射为 App 内路由路径(`/comic/{pathWord}`),
  /// 不是本站的漫画分享链接或 pathWord 非法时返回 null。
  /// 供 app_router.dart 的 `/c` 路由 redirect 使用。
  static String? comicPathFromShareUrl(Uri uri) {
    if (uri.scheme != 'https' || uri.host != webHost) return null;
    if (uri.path != '/c' && uri.path != '/c/') return null;
    final w = uri.queryParameters['w'];
    if (w == null || !_pathWordPattern.hasMatch(w)) return null;
    return '/comic/$w';
  }

  static final _comicNamePattern = RegExp('《(.{1,80}?)》');

  /// 从分享文本中提取《漫画名》，用于提示展示；没有则返回 null。
  static String? extractComicName(String text) =>
      _comicNamePattern.firstMatch(text)?.group(1);
}

/// 「最近一条已处理的漫画分享链接」记录，供 main.dart 的剪贴板检测去重。
///
/// 只保存**一条**记录，新记录直接覆盖旧的：复制链接 A 提示后记 A；再打开
/// 时剪贴板里还是 A → 不提示；复制链接 B → B≠A → 提示并替换为 B；此后
/// 剪贴板里又是 A 时（记录为 B）→ 会再次提示。
///
/// 分享者调起系统分享面板时也会调用 [markHandled]——分享面板关闭时
/// MainActivity 的 onResume 会触发剪贴板检测，预先记录可避免把
/// 自己刚分享的链接又弹给自己。
abstract final class SharedLinkRecord {
  static const _key = 'shared_link_last_handled';

  /// 把 [pathWord] 记为最近一条已处理链接（覆盖旧值）。
  static Future<void> markHandled(String pathWord) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, pathWord);
  }

  /// 最近一条已处理链接的 pathWord，没有则为 null。
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }
}

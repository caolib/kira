import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:system_fonts/system_fonts.dart';

import 'api/copy_settings_auto_updater.dart';
import 'l10n/app_localizations.dart';
import 'models/theme_settings.dart';
import 'models/user_manager.dart';
import 'routing/app_router.dart';
import 'theme/app_radius.dart';
import 'theme/app_typography.dart';
import 'utils/app_logger.dart';
import 'utils/app_storage.dart';
import 'utils/display_mode_preference.dart';
import 'utils/font_manager.dart';
import 'utils/kira_links.dart';
import 'utils/network_proxy.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Drops expired business cache entries once per launch.
///
/// Entries were only ever evicted when something happened to read them again,
/// so caches for content the user stopped opening lingered indefinitely. Runs
/// after a delay so it never competes with first-frame rendering.
Future<void> _clearExpiredCacheInBackground() async {
  await Future<void>.delayed(const Duration(seconds: 5));
  try {
    await AppStorage.cache.clearExpired();
  } catch (e, stack) {
    unawaited(
      AppLogger.instance.recordWarning(
        e,
        stackTrace: stack,
        source: 'startup.clear_expired_cache',
      ),
    );
  }
}

Locale _parseLocale(String raw) {
  // 仅支持 'zh' 和 'zh-Hant'
  if (raw == 'zh-Hant') {
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
  return const Locale('zh');
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogger.instance.init();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(AppLogger.instance.recordFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          AppLogger.instance.recordError(
            error,
            stackTrace: stack,
            source: 'platform_dispatcher',
          ),
        );
        return true;
      };

      // media_kit 原生库在 Android 上按需下载，首次播放时再 ensureInitialized。
      await UserManager().init();
      await NetworkProxy.init();
      // 启动时若 COPY 高级设置过时（>1天），后台自动更新；失败静默。
      CopySettingsAutoUpdater.maybeUpdateOnStartup();
      unawaited(_clearExpiredCacheInBackground());
      if (isDesktop) {
        final font = UserManager().desktopFontFamily;
        if (font.isNotEmpty) {
          try {
            await SystemFonts().loadFont(font);
          } catch (e, stack) {
            unawaited(
              AppLogger.instance.recordError(
                e,
                stackTrace: stack,
                source: 'desktop_font',
              ),
            );
          }
        }
      }
      final appFont = UserManager().theme.appFontFamily;
      if (appFont.isNotEmpty) {
        unawaited(FontManager().ensureFontReady(appFont));
      }
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
      );
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemStatusBarContrastEnforced: false,
        ),
      );
      runApp(const ProviderScope(child: KiraApp()));
    },
    (error, stack) {
      unawaited(
        AppLogger.instance.recordError(
          error,
          stackTrace: stack,
          source: 'zone',
        ),
      );
    },
  );
}

/// 允许鼠标拖拽触发滚动和下拉刷新（桌面端适配）
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class KiraApp extends ConsumerStatefulWidget {
  const KiraApp({super.key});

  @override
  ConsumerState<KiraApp> createState() => _KiraAppState();
}

class _KiraAppState extends ConsumerState<KiraApp> with WidgetsBindingObserver {
  final _user = UserManager();

  /// 根 ScaffoldMessenger，用于在任意页面上方弹出「检测到分享链接」提示。
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 本次会话内已处理过的分享链接内存镜像，避免每次回前台都读 prefs。
  String? _lastHandledSharedPathWord;

  CardThemeData get _cardTheme => CardThemeData(
    clipBehavior: Clip.hardEdge,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
    elevation: _user.theme.cardShadowElevation,
    surfaceTintColor: Colors.transparent,
  );

  // Router 必须只创建一次：若在 build() 里调用 createAppRouter()，
  // 每次 UserManager 通知（任意设置变化都会触发）都会重建 GoRouter，
  // 导致导航栈被重置到 initialLocation '/'（跳回首页）。
  late final GoRouter _router = createAppRouter();

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      DisplayModePreference.applyRefreshRate(_user.displayModeRefreshRate),
    );
    // 冷启动后检测一次剪贴板中的分享链接（浏览器/聊天 App 里点不开
    // kira:// 时，接收方可复制文本后打开 kira 跳转）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkSharedLinkClipboard());
    });
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkSharedLinkClipboard());
    }
  }

  /// 剪贴板里有漫画分享链接时弹 SnackBar，点击「打开」跳转对应详情页。
  Future<void> _checkSharedLinkClipboard() async {
    try {
      if (!await Clipboard.hasStrings()) return;
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text == null || text.isEmpty) return;
      final pathWord = KiraLinks.extractComicPathWord(text);
      if (pathWord == null) return;
      if (pathWord == _lastHandledSharedPathWord) return;
      final handled = await SharedLinkRecord.read();
      if (handled == pathWord) {
        // 分享者（分享时已标记）或之前已提示过——同步内存镜像，本次不再弹。
        _lastHandledSharedPathWord = pathWord;
        return;
      }
      _lastHandledSharedPathWord = pathWord;
      await SharedLinkRecord.markHandled(pathWord);
      final messengerContext = _messengerKey.currentContext;
      if (messengerContext == null || !messengerContext.mounted) return;
      final l10n = AppLocalizations.of(messengerContext)!;
      final name = KiraLinks.extractComicName(text) ?? pathWord;
      _messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.sharedLinkDetected(name)),
            showCloseIcon: true,
            action: SnackBarAction(
              label: l10n.sharedLinkOpen,
              onPressed: () => _router.push('/comic/$pathWord'),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'shared_link_clipboard',
        ),
      );
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _buildTheme(Brightness brightness) {
    final seedColor = _user.themeOption.seedColor;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: _user.themeVariant,
    );

    // 修复“彩虹”等变体会固定生成独立色相（例如粉色）且不随主题色变化的背景问题
    if (_user.themeVariant == DynamicSchemeVariant.rainbow) {
      final standardScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );
      colorScheme = colorScheme.copyWith(
        surface: standardScheme.surface,
        surfaceDim: standardScheme.surfaceDim,
        surfaceBright: standardScheme.surfaceBright,
        surfaceContainerLowest: standardScheme.surfaceContainerLowest,
        surfaceContainerLow: standardScheme.surfaceContainerLow,
        surfaceContainer: standardScheme.surfaceContainer,
        surfaceContainerHigh: standardScheme.surfaceContainerHigh,
        surfaceContainerHighest: standardScheme.surfaceContainerHighest,
        onSurface: standardScheme.onSurface,
        onSurfaceVariant: standardScheme.onSurfaceVariant,
      );
    }

    final appFont = _user.theme.appFontFamily;
    final desktopFont = _user.desktopFontFamily;

    String? resolvedFont;
    if (appFont.isNotEmpty) {
      resolvedFont = appFont;
    } else if (isDesktop && desktopFont.isNotEmpty) {
      resolvedFont = desktopFont;
    }

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      cardTheme: _cardTheme,
      fontFamily: resolvedFont,
    );
  }

  Widget _buildAppContent(BuildContext context, Widget? child) {
    final mediaQuery = MediaQuery.of(context);
    final fontSizeFactor =
        _user.theme.defaultFontSize / ThemeSettings.defaultAppFontSize;

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: AppTypography.composeTextScaler(
          mediaQuery.textScaler,
          fontSizeFactor,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kira',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: _AppScrollBehavior(),
      builder: _buildAppContent,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _user.themeMode,
      routerConfig: _router,
      scaffoldMessengerKey: _messengerKey,
      locale: _user.locale.isEmpty ? null : _parseLocale(_user.locale),
    );
  }
}

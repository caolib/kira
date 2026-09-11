import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_color_utilities/palettes/core_palettes.dart';
import 'package:material_color_utilities/palettes/tonal_palette.dart';
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
import 'utils/download_manager.dart';
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

      await UserManager().init();
      await NetworkProxy.init();
      // 恢复持久化的下载队列并自动续传（队列空时无操作）。
      await DownloadManager().init();
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

  /// Android 12+ 系统动态取色调色板（Monet），启动时异步获取一次。
  ///
  /// 与 dynamic_color 插件走同一个平台通道（依赖保留在 pubspec 里以注册
  /// Android 端 handler），但直接解析返回的色调列表，避免其已废弃的
  /// [CorePalette] API。
  static const _dynamicColorChannel = OptionalMethodChannel(
    'io.material.plugins/dynamic_color',
  );

  CorePalettes? _dynamicPalettes;

  Future<void> _loadDynamicPalettes() async {
    try {
      final result = await _dynamicColorChannel.invokeMethod<List<dynamic>?>(
        'getCorePalette',
      );
      if (result == null) return;
      final colors = result.cast<int>();
      final size = TonalPalette.commonSize;
      if (colors.length != size * 5) return;
      TonalPalette partition(int index) => TonalPalette.fromList(
        colors.sublist(index * size, (index + 1) * size),
      );
      _dynamicPalettes = CorePalettes(
        partition(0),
        partition(1),
        partition(2),
        partition(3),
        partition(4),
      );
      if (mounted) setState(() {});
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'dynamic_color.palette',
        ),
      );
    }
  }

  CardThemeData _cardTheme(ColorScheme cs) => CardThemeData(
    clipBehavior: Clip.hardEdge,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
    elevation: _user.theme.cardShadowElevation,
    surfaceTintColor: Colors.transparent,
    // 与全应用卡片色统一（SettingTileGroup 等同款）；显式指定颜色的卡片不受影响。
    color: cs.surfaceBright,
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
    unawaited(_loadDynamicPalettes());
    // 冷启动后检测一次剪贴板中的分享链接（浏览器/聊天 App 里点不开
    // kira:// 时，接收方可复制文本后打开 kira 跳转）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkSharedLinkClipboard());
    });
  }

  /// 由系统 [CorePalettes] 构建 Flutter 的 [ColorScheme]。
  ///
  /// 色调映射遵循 Material 3 的 `Scheme.lightFromCorePalette` /
  /// `Scheme.darkFromCorePalette`；`surfaceContainer*` 档位由中性色调
  /// 推导，与 fromSeed 的梯度保持一致的明暗关系。
  ColorScheme _dynamicColorScheme(CorePalettes palette, Brightness brightness) {
    final light = brightness == Brightness.light;
    final p = palette.primary;
    final s = palette.secondary;
    final t = palette.tertiary;
    final n = palette.neutral;
    final nv = palette.neutralVariant;

    // 标准错误色（与 CorePalette 的固定 error 色调一致：hue 25, chroma 84）。
    final e = TonalPalette.of(25, 84);
    int tone(TonalPalette palette, int lightTone, int darkTone) =>
        palette.get(light ? lightTone : darkTone);
    final surfaceTone = tone(n, 98, 6);
    Color container(int neutralToneLight, int neutralToneDark) =>
        Color(tone(n, neutralToneLight, neutralToneDark));

    return ColorScheme(
      brightness: brightness,
      primary: Color(tone(p, 40, 80)),
      onPrimary: Color(tone(p, 100, 20)),
      primaryContainer: Color(tone(p, 90, 30)),
      onPrimaryContainer: Color(tone(p, 10, 90)),
      secondary: Color(tone(s, 40, 80)),
      onSecondary: Color(tone(s, 100, 20)),
      secondaryContainer: Color(tone(s, 90, 30)),
      onSecondaryContainer: Color(tone(s, 10, 90)),
      tertiary: Color(tone(t, 40, 80)),
      onTertiary: Color(tone(t, 100, 20)),
      tertiaryContainer: Color(tone(t, 90, 30)),
      onTertiaryContainer: Color(tone(t, 10, 90)),
      error: Color(tone(e, 40, 80)),
      onError: Color(tone(e, 100, 20)),
      errorContainer: Color(tone(e, 90, 30)),
      onErrorContainer: Color(tone(e, 10, 90)),
      surface: Color(surfaceTone),
      onSurface: Color(tone(n, 10, 90)),
      surfaceDim: container(87, 11),
      surfaceBright: container(98, 24),
      surfaceContainerLowest: container(100, 4),
      surfaceContainerLow: container(96, 10),
      surfaceContainer: container(94, 12),
      surfaceContainerHigh: container(92, 17),
      surfaceContainerHighest: container(90, 22),
      onSurfaceVariant: Color(tone(nv, 30, 80)),
      outline: Color(tone(nv, 50, 60)),
      outlineVariant: Color(tone(nv, 80, 30)),
      shadow: Color(tone(n, 0, 0)),
      scrim: Color(tone(n, 0, 0)),
      inverseSurface: Color(tone(n, 20, 90)),
      onInverseSurface: Color(tone(n, 95, 20)),
      inversePrimary: Color(tone(p, 80, 40)),
      surfaceTint: Color(tone(p, 40, 80)),
    );
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

  ThemeData _buildTheme(Brightness brightness, [CorePalettes? dynamicPalette]) {
    final seedColor = _user.themeOption.seedColor;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: _user.themeVariant,
    );

    // Android 12+ Monet 动态取色：跟随系统壁纸配色。
    // Android 12+ Monet 动态取色：跟随系统壁纸配色（仅 Android 且开关打开）。
    if (_user.theme.useDynamicColor && dynamicPalette != null) {
      colorScheme = _dynamicColorScheme(dynamicPalette, brightness);
    }

    // 修复“彩虹”等变体会固定生成独立色相（例如粉色）且不随主题色变化的背景问题
    if (_user.themeVariant == DynamicSchemeVariant.rainbow &&
        !_user.theme.useDynamicColor) {
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

    // AMOLED 纯黑模式：暗色下把背景/表面压到纯黑，省电且无拖影。
    if (brightness == Brightness.dark && _user.theme.amoledDark) {
      const black = Color(0xFF000000);
      colorScheme = colorScheme.copyWith(
        surface: black,
        surfaceDim: black,
        surfaceContainerLowest: black,
        surfaceContainerLow: black,
        surfaceContainer: black,
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

    // RikkaHub 式背景分层：亮色下页面背景用 surfaceContainer（比卡片的
    // surfaceBright 深 4 档色调），阴影关掉也靠纯色对比区分层级；暗色下
    // surface(T6) 与 surfaceBright(T24) 本就差 18 档，保持默认。
    final pageColor = brightness == Brightness.light
        ? colorScheme.surfaceContainer
        : colorScheme.surface;

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: pageColor,
      appBarTheme: AppBarTheme(
        backgroundColor: pageColor,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: _cardTheme(colorScheme),
      // 组件级圆角阶梯：卡片 lg(16) / 对话框与弹层 xl(20)。弹层外观统一由
      // AppSheet / showAppSheet 承载，这里兜底所有直接用系统组件的调用点。
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      // SnackBar 与自定义 Toast 同为“悬浮圆角条”观感，避免两套通知皮。
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
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
      theme: _buildTheme(Brightness.light, _dynamicPalettes),
      darkTheme: _buildTheme(Brightness.dark, _dynamicPalettes),
      themeMode: _user.themeMode,
      routerConfig: _router,
      scaffoldMessengerKey: _messengerKey,
      locale: _user.locale.isEmpty ? null : _parseLocale(_user.locale),
    );
  }
}

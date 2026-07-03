import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:system_fonts/system_fonts.dart';

import 'l10n/app_localizations.dart';
import 'models/user_manager.dart';
import 'routing/app_router.dart';
import 'utils/app_logger.dart';
import 'utils/display_mode_preference.dart';
import 'utils/network_proxy.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

      if (!Platform.isWindows) {
        MediaKit.ensureInitialized();
      }
      await UserManager().init();
      await NetworkProxy.init();
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

class _KiraAppState extends ConsumerState<KiraApp> {
  final _user = UserManager();

  static final _cardTheme = CardThemeData(
    clipBehavior: Clip.hardEdge,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
  );

  // Router 必须只创建一次：若在 build() 里调用 createAppRouter()，
  // 每次 UserManager 通知（任意设置变化都会触发）都会重建 GoRouter，
  // 导致导航栈被重置到 initialLocation '/'（跳回首页）。
  late final GoRouter _router = createAppRouter();

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
    unawaited(
      DisplayModePreference.applyRefreshRate(_user.displayModeRefreshRate),
    );
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
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

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      cardTheme: _cardTheme,
      fontFamily: isDesktop && _user.desktopFontFamily.isNotEmpty
          ? _user.desktopFontFamily
          : null,
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
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _user.themeMode,
      routerConfig: _router,
      locale:
          _user.locale.isEmpty
              ? null
              : _parseLocale(_user.locale),
    );
  }
}

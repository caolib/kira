import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:system_fonts/system_fonts.dart';

import 'models/user_manager.dart';
import 'pages/anime_home_page.dart';
import 'pages/bookshelf_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';
import 'utils/app_logger.dart';
import 'utils/app_update.dart';
import 'utils/display_mode_preference.dart';
import 'utils/network_proxy.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

      MediaKit.ensureInitialized();
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
      unawaited(SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ));
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemStatusBarContrastEnforced: false,
        ),
      );
      runApp(const KiraApp());
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

class KiraApp extends StatefulWidget {
  const KiraApp({super.key});

  @override
  State<KiraApp> createState() => _KiraAppState();
}

class _KiraAppState extends State<KiraApp> {
  final _user = UserManager();

  static final _cardTheme = CardThemeData(
    clipBehavior: Clip.hardEdge,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
  );

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
    return MaterialApp(
      title: 'Kira',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _user.themeMode,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _DisclaimerDialog extends StatefulWidget {
  final List<String> items;
  final String confirmLabel;

  const _DisclaimerDialog({required this.items, required this.confirmLabel});

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('免责声明'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in widget.items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: tt.bodyMedium),
                            Expanded(child: Text(item, style: tt.bodyMedium)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并退出本应用。',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _accepted,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.confirmLabel),
                onChanged: (value) {
                  setState(() => _accepted = value ?? false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('不同意并退出'),
          ),
          FilledButton(
            onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

class _MainPageState extends State<MainPage> {
  final _user = UserManager();
  String _selectedNavKey = UserManager.defaultNavKey;
  bool _didAutoCheckUpdate = false;
  bool _didCheckDisclaimer = false;

  static const _disclaimerItems = [
    '本应用（以下简称"本软件"）系独立开发的非官方第三方客户端，与任何内容平台、出版商或权利人均无隶属、合作或代理关系。',
    '本软件不生产、上传、存储、编辑、修改、推荐或预先审查任何具体内容。所有内容均来源于第三方平台公开接口或可访问资源，其合法性、准确性、完整性及合规性由相应内容提供方独立负责。',
    '本软件所展示的内容可能包含成人向、暴力、恐怖或其他不适宜未成年人浏览的信息。您确认您已年满 18 周岁，且您所在地法律法规允许您访问此类内容。如您不符合前述条件，请立即停止使用并卸载本软件。',
    '您应自行判断所浏览内容是否适合，并确保您的使用行为完全符合您所在地现行有效的法律法规。因您使用本软件而产生的一切法律后果由您自行承担。',
    '如任何第三方内容涉嫌侵犯他人合法权益或违反法律法规，权利人可通过本软件提供的联系方式向开发者发送有效通知，开发者将在合理期限内核实并采取必要措施。',
    '本软件按"现状"提供，开发者不对其功能性、可用性、准确性或可靠性作出任何明示或默示的保证。在任何情况下，开发者均不对因使用或无法使用本软件而产生的任何直接、间接、附带、特殊或后果性损害承担责任。',
  ];

  static const _disclaimerConfirmText = '我已年满 18 周岁，并已仔细阅读、充分理解且同意上述全部条款';

  List<String> get _disclaimerItemsList => _disclaimerItems;
  String get _disclaimerConfirmLabel => _disclaimerConfirmText;

  @override
  void initState() {
    super.initState();
    final visibleKeys = _visibleNavKeys();
    _selectedNavKey = _resolveVisibleNavKey(_user.lastNavKey, visibleKeys);
    if (_selectedNavKey != _user.lastNavKey) {
      unawaited(_user.setLastNavKey(_selectedNavKey));
    }
    _user.addListener(_onUserChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupFlow();
    });
  }

  Future<void> _runStartupFlow() async {
    await _ensureDisclaimerAccepted();
    if (!mounted) return;

    await _maybeAutoCheckUpdate();
  }

  Future<void> _ensureDisclaimerAccepted() async {
    if (_didCheckDisclaimer || _user.disclaimerAccepted || !mounted) return;
    _didCheckDisclaimer = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisclaimerDialog(
        items: _disclaimerItemsList,
        confirmLabel: _disclaimerConfirmLabel,
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      await _user.setDisclaimerAccepted(true);
    }
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    final visibleKeys = _visibleNavKeys();
    final nextNavKey = _resolveVisibleNavKey(_selectedNavKey, visibleKeys);
    if (nextNavKey != _selectedNavKey) {
      unawaited(_user.setLastNavKey(nextNavKey));
    }
    setState(() {
      _selectedNavKey = nextNavKey;
    });
  }

  Future<void> _maybeAutoCheckUpdate() async {
    if (!mounted || _didAutoCheckUpdate || !_user.autoCheckUpdate) return;
    _didAutoCheckUpdate = true;
    await AppUpdateService.checkAndPrompt(context, auto: true);
  }

  // 可见 tabs 取决于登录状态和动漫功能开关；外观页仍保留完整顺序。

  static final _navItemData = {
    'comic': const _NavItem(
      page: HomePage(),
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: '漫画',
    ),
    'anime': const _NavItem(
      page: AnimeHomePage(),
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      label: '动漫',
    ),
    'search': const _NavItem(
      page: SearchPage(),
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: '搜索',
    ),
    'bookshelf': const _NavItem(
      page: BookshelfPage(),
      icon: Icon(Icons.bookmark_border),
      selectedIcon: Icon(Icons.bookmark),
      label: '书架',
    ),
    'profile': const _NavItem(
      page: ProfilePage(),
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  };

  List<String> _visibleNavKeys() {
    final keys = _user.navOrder
        .where(_navItemData.containsKey)
        .where((k) => _user.isLoggedIn || k != 'bookshelf')
        .where((k) => _user.animeFeatureEnabled || k != 'anime')
        .toList();
    return keys.isEmpty ? const [UserManager.defaultNavKey] : keys;
  }

  String _resolveVisibleNavKey(String navKey, List<String> visibleKeys) {
    if (visibleKeys.contains(navKey)) return navKey;
    if (visibleKeys.contains(UserManager.defaultNavKey)) {
      return UserManager.defaultNavKey;
    }
    return visibleKeys.isEmpty ? UserManager.defaultNavKey : visibleKeys.first;
  }

  int _selectedIndex(List<String> orderedKeys) {
    final selectedKey = _resolveVisibleNavKey(_selectedNavKey, orderedKeys);
    final index = orderedKeys.indexOf(selectedKey);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final orderedKeys = _visibleNavKeys();
    final destinations = [
      for (final key in orderedKeys)
        NavigationDestination(
          icon: _navItemData[key]!.icon,
          selectedIcon: _navItemData[key]!.selectedIcon,
          label: _navItemData[key]!.label,
        ),
    ];
    final orderedPages = [
      for (final key in orderedKeys) _navItemData[key]!.page,
    ];
    final selectedIndex = _selectedIndex(orderedKeys);

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: orderedPages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          final navKey = orderedKeys[i];
          setState(() => _selectedNavKey = navKey);
          unawaited(_user.setLastNavKey(navKey));
        },
        height: _user.bottomNavShowLabels ? null : 64,
        labelBehavior: _user.bottomNavShowLabels
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.alwaysHide,
        destinations: destinations,
      ),
    );
  }
}

class _NavItem {
  final Widget page;
  final Icon icon;
  final Icon selectedIcon;
  final String label;
  const _NavItem({
    required this.page,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

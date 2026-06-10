import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:system_fonts/system_fonts.dart';

import 'models/user_manager.dart';
import 'pages/anime_home_page.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/bookshelf_page.dart';
import 'pages/profile_page.dart';
import 'utils/app_update.dart';
import 'utils/network_proxy.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await UserManager().init();
  await NetworkProxy.init();
  if (isDesktop) {
    final font = UserManager().desktopFontFamily;
    if (font.isNotEmpty) {
      try {
        await SystemFonts().loadFont(font);
      } catch (_) {}
    }
  }
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
  );
  runApp(const KiraApp());
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
    '本应用为非官方第三方客户端，仅基于第三方平台提供的接口或公开可访问资源进行内容展示与访问。',
    '本应用不生产、上传、编辑、修改或预先审查具体展示内容，相关内容均来源于第三方返回结果，开发者无法对其进行完全控制。',
    '本应用展示的内容中，可能包含成人内容或其他不适宜未成年人浏览的信息；如您未满 18 周岁，或您所在地法律法规禁止访问相关内容，请立即停止使用本应用。',
    '用户应自行判断相关内容是否适合浏览，并确保其使用行为符合所在地法律法规。',
    '如第三方内容存在侵权、违法、违规或其他不当情形，相关责任原则上由内容提供方承担；开发者将在收到有效通知后，根据实际情况采取必要处理措施。',
  ];

  static const _disclaimerConfirmText = '我已年满 18 周岁，并已阅读、理解且同意上述免责声明';

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
    'comic': _NavItem(
      page: HomePage(),
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: '漫画',
    ),
    'anime': _NavItem(
      page: AnimeHomePage(),
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      label: '动漫',
    ),
    'search': _NavItem(
      page: SearchPage(),
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: '搜索',
    ),
    'bookshelf': _NavItem(
      page: BookshelfPage(),
      icon: Icon(Icons.bookmark_border),
      selectedIcon: Icon(Icons.bookmark),
      label: '书架',
    ),
    'profile': _NavItem(
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

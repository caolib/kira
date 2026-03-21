import 'package:flutter/material.dart';
import 'models/user_manager.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/bookshelf_page.dart';
import 'pages/profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserManager().init();
  runApp(const KiraApp());
}

class KiraApp extends StatelessWidget {
  const KiraApp({super.key});

  static const _seed = Color(0xFF6750A4);

  static final _cardTheme = CardThemeData(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kira',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _seed,
        useMaterial3: true,
        brightness: Brightness.light,
        cardTheme: _cardTheme,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        useMaterial3: true,
        brightness: Brightness.dark,
        cardTheme: _cardTheme,
      ),
      themeMode: ThemeMode.system,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;
  final _user = UserManager();

  static const _allPages = [
    HomePage(),
    SearchPage(),
    BookshelfPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    if (!_user.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      });
    }
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    setState(() {
      final maxIndex = _user.isLoggedIn ? 3 : 2;
      if (_index > maxIndex) _index = 0;
    });
  }

  // 未登录时 tabs: [首页(0), 发现(1), 我的(2)]
  // 登录后 tabs: [首页(0), 发现(1), 书架(2), 我的(3)]
  int get _pageIndex {
    if (_user.isLoggedIn) return _index;
    const map = [0, 1, 3]; // tab index → page index
    return map[_index.clamp(0, 2)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _pageIndex, children: _allPages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          if (_user.isLoggedIn)
            const NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: '书架',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

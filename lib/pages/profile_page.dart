import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../utils/app_update.dart';
import '../utils/toast.dart';
import 'local_comics_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _user = UserManager();

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  void _goLogin() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (result == true) setState(() {});
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _user.logout();
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      await _user.refreshUserInfo();
      if (mounted) {
        showToast(context, '用户信息已刷新');
      }
    } catch (_) {
      if (mounted) {
        showToast(context, '刷新失败，请重试', isError: true);
      }
    }
  }

  Future<void> _copyToken() async {
    final token = _user.token;
    if (token == null || token.isEmpty) {
      showToast(context, '暂无可复制的令牌', isError: true);
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      showToast(context, '令牌已复制到剪贴板');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _user.isLoggedIn
                  ? _buildUserCard(cs, tt)
                  : _buildLoginCard(cs, tt),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: cs.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.palette_outlined,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 16),
                                const Text('主题模式'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    icon: Icon(Icons.settings_brightness),
                                    label: Text('系统'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    icon: Icon(Icons.light_mode),
                                    label: Text('浅色'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    icon: Icon(Icons.dark_mode),
                                    label: Text('深色'),
                                  ),
                                ],
                                selected: {_user.themeMode},
                                onSelectionChanged: (v) =>
                                    _user.setThemeMode(v.first),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      if (_user.isLoggedIn &&
                          _user.savedUsername != null &&
                          _user.savedPassword != null)
                        SwitchListTile(
                          secondary: const Icon(Icons.login),
                          title: const Text('自动登录'),
                          subtitle: const Text('登录过期时自动重新登录'),
                          value: _user.autoLogin,
                          onChanged: _user.setAutoLogin,
                        ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.download_done_outlined),
                        title: const Text('本地漫画'),
                        subtitle: const Text('查看和管理已下载的漫画章节'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LocalComicsPage(),
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('关于'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AboutPage()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(ColorScheme cs, TextTheme tt) {
    return Card(
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _goLogin,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: cs.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: 32,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('未登录', style: tt.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '点击登录以使用书架等功能',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(ColorScheme cs, TextTheme tt) {
    return Column(
      children: [
        Card(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: cs.primaryContainer,
                  child:
                      _user.avatar != null && _user.avatar!.startsWith('http')
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _user.avatar!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 32,
                          color: cs.onPrimaryContainer,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user.nickname ?? _user.username ?? '',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildUserActionButton(
                icon: Icons.refresh,
                label: '刷新用户信息',
                onPressed: () => _refreshUserInfo(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildUserActionButton(
                icon: Icons.copy_outlined,
                label: '复制令牌',
                onPressed: () => _copyToken(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildUserActionButton(
                icon: Icons.logout,
                label: '退出登录',
                onPressed: () => _logout(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 登录页 ──

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _api = ApiClient();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _useToken = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = UserManager();
    if (user.savedUsername != null) {
      _usernameCtrl.text = user.savedUsername!;
      _rememberMe = true;
    }
    if (user.savedPassword != null) {
      _passwordCtrl.text = user.savedPassword!;
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _api.login(username, password);
      if (_rememberMe) {
        await UserManager().saveCredentials(username, password);
      } else {
        await UserManager().clearCredentials();
      }
      await UserManager().saveLogin(
        token: result['token'],
        userId: result['user_id'],
        username: result['username'],
        nickname: result['nickname'] ?? result['username'],
        avatar: result['avatar'] ?? '',
      );
      await UserManager().refreshUserInfo();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      String msg = '登录失败';
      if (e is DioException && e.response?.data is Map) {
        msg = e.response?.data['message'] ?? msg;
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  Future<void> _loginWithToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = '请输入令牌');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 先临时保存 token 以便 API 请求携带 Authorization
      await UserManager().saveLogin(
        token: token,
        userId: '',
        username: '',
        nickname: '',
        avatar: '',
      );
      // 用 token 拉取用户信息验证有效性
      final info = await _api.getUserInfo();
      await UserManager().saveLogin(
        token: token,
        userId: info['user_id']?.toString() ?? '',
        username: info['username']?.toString() ?? '',
        nickname:
            info['nickname']?.toString() ?? info['username']?.toString() ?? '',
        avatar: info['avatar']?.toString() ?? '',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 令牌无效，清除
      await UserManager().logout();
      String msg = '令牌无效或已过期';
      if (e is DioException && e.response?.data is Map) {
        msg = e.response?.data['message'] ?? msg;
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 400.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 48, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/ic_launcher.png', width: 64, height: 64),
            const SizedBox(height: 16),
            Text(
              'Kira',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('账号密码'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('令牌'),
                  icon: Icon(Icons.key),
                ),
              ],
              selected: {_useToken},
              onSelectionChanged: (v) => setState(() {
                _useToken = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 24),
            if (!_useToken) ...[
              TextField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: '用户名',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
            ] else ...[
              TextField(
                controller: _tokenCtrl,
                decoration: InputDecoration(
                  labelText: '令牌 (Token)',
                  prefixIcon: const Icon(Icons.key),
                  hintText: '粘贴你的登录令牌',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loginWithToken(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            if (!_useToken) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: const Text('记住账号'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading
                  ? null
                  : (_useToken ? _loginWithToken : _login),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 关于页 ──

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final _user = UserManager();

  static const _repoUrl = 'https://github.com/caolib/kira';

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.hasData
              ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
              : '...';

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            children: [
              Image.asset('assets/ic_launcher.png', width: 80, height: 80),
              const SizedBox(height: 16),
              Text(
                'Kira',
                textAlign: TextAlign.center,
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '版本 $version',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Card(
                color: cs.surfaceContainerLow,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.system_update_alt),
                      title: const Text('检查更新'),
                      subtitle: Text(
                        _user.skippedUpdateVersion != null &&
                                _user.skippedUpdateVersion!.isNotEmpty
                            ? '已跳过版本 ${_user.skippedUpdateVersion}'
                            : (_user.autoCheckUpdate
                                  ? '自动检查更新：已开启'
                                  : '自动检查更新：已关闭'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AppUpdateService.checkAndPrompt(context),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew),
                      title: const Text('启动时自动检查更新'),
                      value: _user.autoCheckUpdate,
                      onChanged: _user.setAutoCheckUpdate,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('源代码'),
                      subtitle: const Text('caolib/kira'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        await launchUrl(
                          Uri.parse(_repoUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

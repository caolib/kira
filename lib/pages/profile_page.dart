import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/user_manager.dart';

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
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (confirm == true) {
      await _user.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('我的'), pinned: true),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _user.isLoggedIn ? _buildUserCard(cs, tt) : _buildLoginCard(cs, tt),
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
                child: Icon(Icons.person, size: 32, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('未登录', style: tt.titleMedium),
                    const SizedBox(height: 4),
                    Text('点击登录以使用书架等功能',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                  child: _user.avatar != null && _user.avatar!.startsWith('http')
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _user.avatar!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(Icons.person, size: 32, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_user.nickname ?? _user.username ?? '',
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('UID: ${_user.userId ?? ''}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
        ),
      ],
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
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
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
            Icon(Icons.menu_book, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text('Kira',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: '用户名',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? false),
              title: const Text('记住账号'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

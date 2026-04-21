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
import 'appearance_page.dart';
import 'browse_history_page.dart';
import 'local_comics_page.dart';
import 'network_page.dart';

const _appDisclaimerItems = [
  '本应用为非官方第三方客户端，仅基于第三方平台提供的接口或公开可访问资源进行内容展示与访问。',
  '本应用不生产、上传、编辑、修改或预先审查具体展示内容，相关内容均来源于第三方返回结果，开发者无法对其进行完全控制。',
  '本应用展示的内容中，可能包含成人内容或其他不适宜未成年人浏览的信息；如您未满 18 周岁，或您所在地法律法规禁止访问相关内容，请立即停止使用本应用。',
  '用户应自行判断相关内容是否适合浏览，并确保其使用行为符合所在地法律法规。',
  '如第三方内容存在侵权、违法、违规或其他不当情形，相关责任原则上由内容提供方承担；开发者将在收到有效通知后，根据实际情况采取必要处理措施。',
];

const _appDisclaimerFooter = '继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并卸载本应用。';

enum _SwitchAccountSheetAction { addAccount }

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _user = UserManager();
  bool _userActionsExpanded = false;

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

  void _switchAccount() async {
    final credentials = _user.savedCredentials;
    final otherAccounts = credentials
        .where((c) => c.username != _user.username)
        .toList();
    final hasToken = otherAccounts.any(
      (c) => c.token != null && c.token!.isNotEmpty,
    );

    // 没有其他账号或没有存储令牌，回退到登录页
    if (otherAccounts.isEmpty || !hasToken) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        showToast(context, '账号已切换');
        setState(() {});
      }
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '切换账号',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...otherAccounts.map((cred) {
              final displayName = cred.nickname ?? cred.username;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ),
                title: Text(displayName),
                subtitle: Text(cred.username),
                trailing: const Icon(Icons.swap_horiz),
                onTap: () => Navigator.pop(ctx, cred),
              );
            }),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    _SwitchAccountSheetAction.addAccount,
                  ),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('添加账号'),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    if (selected == _SwitchAccountSheetAction.addAccount) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        showToast(context, '账号已切换');
        setState(() {});
      }
      return;
    }

    if (selected is! SavedCredential) return;

    if (selected.token != null && selected.token!.isNotEmpty) {
      final success = await _user.switchToCredential(selected);
      if (mounted) {
        if (success) {
          showToast(context, '账号已切换');
        } else {
          showToast(context, '切换失败，请重试', isError: true);
        }
      }
    } else {
      // 该账号无令牌，回退到登录页
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        showToast(context, '账号已切换');
        setState(() {});
      }
    }
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
      try {
        await ApiClient().logout();
      } catch (e) {
        debugPrint('ProfilePage logout error: $e');
      } finally {
        await _user.logout();
      }
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
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('外观'),
                        subtitle: Text(
                          '${_user.themeOption.label} · ${_user.themeMode == ThemeMode.system ? '跟随系统' : _user.themeMode == ThemeMode.light ? '浅色' : '深色'}',
                          style: tt.bodySmall,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppearancePage(),
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('网络'),
                        subtitle: Text(
                          'API 线路 ${_user.apiRoute + 1}',
                          style: tt.bodySmall,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NetworkPage(),
                          ),
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
                        leading: const Icon(Icons.history),
                        title: const Text('浏览记录'),
                        subtitle: const Text('查看最近浏览过的漫画'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BrowseHistoryPage(
                              loginPageBuilder: (_) => const LoginPage(),
                            ),
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
    return Card(
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _userActionsExpanded = !_userActionsExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                    child: Text(
                      _user.nickname ?? _user.username ?? '',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _userActionsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _userActionsExpanded
                    ? Column(
                        children: [
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final buttonWidth =
                                  (constraints.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.refresh,
                                      label: '刷新用户',
                                      onPressed: () => _refreshUserInfo(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.switch_account,
                                      label: '切换账号',
                                      onPressed: () => _switchAccount(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.copy_outlined,
                                      label: '复制令牌',
                                      onPressed: () => _copyToken(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.logout,
                                      label: '退出登录',
                                      onPressed: () => _logout(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
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

class _RegisterPrefill {
  final String username;
  final String password;

  const _RegisterPrefill({required this.username, required this.password});
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _api = ApiClient();
  final _user = UserManager();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _useToken = false;
  bool _useCopyLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_user.savedUsername != null) {
      _usernameCtrl.text = _user.savedUsername!;
      _rememberMe = true;
    }
    if (_user.savedPassword != null) {
      _passwordCtrl.text = _user.savedPassword!;
    }
    _user.addListener(_onUserChanged);
    _useCopyLogin = _user.loginSource == 'copy';
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  void _applySavedCredential(SavedCredential credential) {
    setState(() {
      _useToken = false;
      _rememberMe = true;
      _error = null;
      _usernameCtrl.text = credential.username;
      _passwordCtrl.text = credential.password;
    });
  }

  Future<void> _removeSavedCredential(SavedCredential credential) async {
    await _user.removeSavedCredential(credential.username);
    if (!mounted) return;
    if (_usernameCtrl.text.trim() == credential.username) {
      setState(() {
        final next = _user.savedCredentials.isNotEmpty
            ? _user.savedCredentials.first
            : null;
        _usernameCtrl.text = next?.username ?? '';
        _passwordCtrl.text = next?.password ?? '';
        _rememberMe = next != null;
      });
    }
    showToast(context, '已移除 ${credential.username}');
  }

  Future<void> _goRegister() async {
    final result = await Navigator.push<_RegisterPrefill>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
    if (result == null || !mounted) return;

    await UserManager().saveCredentials(result.username, result.password);
    if (!mounted) return;
    setState(() {
      _useToken = false;
      _rememberMe = true;
      _error = null;
      _usernameCtrl.text = result.username;
      _passwordCtrl.text = result.password;
    });
    showToast(context, '注册成功，请登录');
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
      final result = _useCopyLogin
          ? await _api.copyLogin(username, password)
          : await _api.login(username, password);
      await UserManager().setLoginSource(_useCopyLogin ? 'copy' : 'hotmanga');
      if (_rememberMe) {
        await UserManager().saveCredentials(username, password);
      } else {
        await UserManager().removeSavedCredential(username);
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
      if (e is DioException) {
        if (e.response?.data is Map) {
          msg = e.response?.data['message'] ?? msg;
        } else if (e.message != null && e.message!.isNotEmpty) {
          msg = e.message!;
        }
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('热辣'),
                    icon: Icon(Icons.phone_android, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('拷贝'),
                    icon: Icon(Icons.language, size: 18),
                  ),
                ],
                selected: {_useCopyLogin},
                onSelectionChanged: (v) => setState(() {
                  _useCopyLogin = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              if (_user.savedCredentials.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _user.savedCredentials.map((credential) {
                    return InputChip(
                      label: Text(credential.username),
                      avatar: const Icon(Icons.person, size: 18),
                      onPressed: () => _applySavedCredential(credential),
                      onDeleted: () => _removeSavedCredential(credential),
                      deleteIcon: const Icon(Icons.close, size: 18),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading ? null : _goRegister,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('注册账号'),
                ),
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

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const _fallbackQuestions = [
    '我的老婆叫什麼？',
    '我的基友叫啥？',
    '我的好麻吉有幾個？',
    '我的父親(母親)叫什麽？',
  ];

  final _api = ApiClient();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  List<String> _questions = [];
  String? _selectedQuestion;
  bool _loadingQuestions = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loadingQuestions = true;
      _error = null;
    });

    try {
      final questions = await _api.getSecurityQuestions();
      if (!mounted) return;
      final availableQuestions = questions.isNotEmpty
          ? questions
          : _fallbackQuestions;
      setState(() {
        _questions = availableQuestions;
        _selectedQuestion = availableQuestions.first;
        _loadingQuestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _questions = _fallbackQuestions;
        _selectedQuestion = _fallbackQuestions.first;
        _loadingQuestions = false;
        _error = null;
      });
    }
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    final answer = _answerCtrl.text.trim();

    if (username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        answer.isEmpty) {
      setState(() => _error = '请填写完整注册信息');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    if (_selectedQuestion == null || _selectedQuestion!.isEmpty) {
      setState(() => _error = '请选择安全问题');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _api.register(
        username: username,
        password: password,
        question: _selectedQuestion!,
        answer: answer,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _RegisterPrefill(username: username, password: password),
      );
    } catch (e) {
      String msg = '注册失败';
      if (e is DioException) {
        msg = e.message ?? msg;
        if (e.response?.data is Map) {
          final data = e.response?.data as Map;
          final results = data['results'];
          msg =
              data['message']?.toString() ??
              data['detail']?.toString() ??
              (results is Map ? results['detail']?.toString() : null) ??
              msg;
        }
      }
      if (!mounted) return;
      setState(() {
        _error = msg;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 420.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 24, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '确认密码',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            if (_loadingQuestions)
              const Center(child: CircularProgressIndicator())
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedQuestion,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '账号安全问题',
                  prefixIcon: const Icon(Icons.help_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _questions
                    .map(
                      (q) => DropdownMenuItem<String>(
                        value: q,
                        child: Text(q, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedQuestion = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _answerCtrl,
                decoration: InputDecoration(
                  labelText: '安全问题答案',
                  prefixIcon: const Icon(Icons.shield_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _register(),
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
            if (!_loadingQuestions && _questions.isEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadQuestions,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载安全问题'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting || _loadingQuestions ? null : _register,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('注册', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('免责声明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            '请在使用本应用前仔细阅读以下声明：',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in _appDisclaimerItems) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: tt.bodyMedium),
                        Expanded(child: Text(item, style: tt.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _appDisclaimerFooter,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('免责声明'),
                      subtitle: const Text('查看应用使用声明与内容说明'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DisclaimerPage(),
                        ),
                      ),
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

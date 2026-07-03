import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../utils/toast.dart';
import 'register_page.dart' show RegisterPrefill;

List<BoxShadow> _profileCardShadow(ColorScheme cs) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.08),
    blurRadius: 18,
    offset: const Offset(0, 6),
  ),
  BoxShadow(
    color: cs.shadow.withValues(alpha: 0.04),
    blurRadius: 6,
    offset: const Offset(0, 2),
  ),
];

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
    _usernameCtrl.addListener(_onCredentialDraftChanged);
    _user.addListener(_onUserChanged);
    _useCopyLogin = _user.loginSource == 'copy';
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _usernameCtrl.removeListener(_onCredentialDraftChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  void _onCredentialDraftChanged() {
    if (mounted) setState(() {});
  }

  bool _isCopyCredential(SavedCredential credential) {
    final source = credential.loginSource;
    if (source != null && source.isNotEmpty) {
      return source == 'copy';
    }
    if (credential.username == _user.savedUsername) {
      return _user.loginSource == 'copy';
    }
    return false;
  }

  String _credentialTypeLabel(SavedCredential credential) {
    return _isCopyCredential(credential) ? '拷贝' : '热辣';
  }

  IconData _credentialTypeIcon(SavedCredential credential) {
    return _isCopyCredential(credential) ? Icons.language : Icons.phone_android;
  }

  bool _isCredentialSelected(SavedCredential credential) {
    return !_useToken &&
        _usernameCtrl.text.trim() == credential.username &&
        _useCopyLogin == _isCopyCredential(credential);
  }

  Widget _buildCredentialBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCredentialCard(
    BuildContext context,
    SavedCredential credential,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCopy = _isCopyCredential(credential);
    final isSelected = _isCredentialSelected(credential);
    final nickname = credential.nickname?.trim();
    final typeBackgroundColor = isCopy
        ? cs.tertiaryContainer
        : cs.secondaryContainer;
    final typeForegroundColor = isCopy
        ? cs.onTertiaryContainer
        : cs.onSecondaryContainer;
    final initial = credential.username.isNotEmpty
        ? credential.username.substring(0, 1).toUpperCase()
        : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant),
        boxShadow: _profileCardShadow(cs),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _applySavedCredential(credential),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSelected
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  child: Text(
                    initial,
                    style: tt.titleMedium?.copyWith(
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credential.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (nickname != null &&
                          nickname.isNotEmpty &&
                          nickname != credential.username) ...[
                        const SizedBox(height: 2),
                        Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildCredentialBadge(
                            context: context,
                            icon: _credentialTypeIcon(credential),
                            label: _credentialTypeLabel(credential),
                            backgroundColor: typeBackgroundColor,
                            foregroundColor: typeForegroundColor,
                          ),
                          if (isSelected)
                            _buildCredentialBadge(
                              context: context,
                              icon: Icons.check_circle,
                              label: '当前已选',
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '移除账号',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeSavedCredential(credential),
                  icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applySavedCredential(SavedCredential credential) {
    setState(() {
      _useToken = false;
      _useCopyLogin = _isCopyCredential(credential);
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
        if (next != null) {
          _useCopyLogin = _isCopyCredential(next);
        }
        _rememberMe = next != null;
      });
    }
    showToast(context, '已移除 ${credential.username}');
  }

  Future<void> _goRegister() async {
    final result = await context.pushNamed<RegisterPrefill>(AppRoutes.register);
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
          ? await _api.user.copyLogin(username, password)
          : await _api.user.login(username, password);
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
      final info = await _api.user.getUserInfo();
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
            Image.asset(_user.appLogoPath, width: 64, height: 64),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '已保存账号',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点按快速填充账号密码，右侧可移除',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Column(
                  children: [
                    for (var i = 0; i < _user.savedCredentials.length; i++) ...[
                      _buildSavedCredentialCard(
                        context,
                        _user.savedCredentials[i],
                      ),
                      if (i != _user.savedCredentials.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
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
                  label: const Text('注册热辣漫画账号'),
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

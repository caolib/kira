import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/toast.dart';
import 'register_page.dart' show RegisterPrefill;

List<BoxShadow> _profileCardShadow(ColorScheme cs) => AppShadows.md(cs);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static final _hotMangaRegisterUri = Uri.parse(
    'https://m.manga2026.xyz/v2h5/register',
  );
  static Uri get _copyMangaRegisterUri => Uri.parse(
    'https://${UserManager().copyLoginHost}/web/login/loginByAccount',
  );

  final _api = ApiClient();
  final _user = UserManager();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
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

  String _credentialTypeLabel(
    BuildContext context,
    SavedCredential credential,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return _isCopyCredential(credential)
        ? l10n.profileCopyCredentialLabel
        : l10n.profileHotCredentialLabel;
  }

  IconData _credentialTypeIcon(SavedCredential credential) {
    return _isCopyCredential(credential) ? Icons.language : Icons.phone_android;
  }

  bool _isCredentialSelected(SavedCredential credential) {
    return _usernameCtrl.text.trim() == credential.username &&
        _useCopyLogin == _isCopyCredential(credential);
  }

  List<SavedCredential> _savedCredentialsForSource(bool useCopyLogin) => _user
      .savedCredentials
      .where((credential) => _isCopyCredential(credential) == useCopyLogin)
      .toList();

  List<SavedCredential> get _visibleSavedCredentials =>
      _savedCredentialsForSource(_useCopyLogin);

  void _selectLoginSource(bool useCopyLogin) {
    final credentials = _savedCredentialsForSource(useCopyLogin);
    final next = credentials.isNotEmpty ? credentials.first : null;
    setState(() {
      _useCopyLogin = useCopyLogin;
      _rememberMe = next != null;
      _error = null;
      _usernameCtrl.text = next?.username ?? '';
      _passwordCtrl.text = next?.password ?? '';
    });
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
        borderRadius: AppRadius.fullR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: AppSpacing.xs),
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
        borderRadius: AppRadius.lgR,
        border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant),
        boxShadow: _profileCardShadow(cs),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.lgR,
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
                const SizedBox(width: AppSpacing.md),
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
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildCredentialBadge(
                            context: context,
                            icon: _credentialTypeIcon(credential),
                            label: _credentialTypeLabel(context, credential),
                            backgroundColor: typeBackgroundColor,
                            foregroundColor: typeForegroundColor,
                          ),
                          if (isSelected)
                            _buildCredentialBadge(
                              context: context,
                              icon: Icons.check_circle,
                              label: AppLocalizations.of(
                                context,
                              )!.profileCurrentSelectedCredential,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(
                    context,
                  )!.profileRemoveAccountTooltip,
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
        final remaining = _savedCredentialsForSource(_useCopyLogin);
        final next = remaining.isNotEmpty ? remaining.first : null;
        _usernameCtrl.text = next?.username ?? '';
        _passwordCtrl.text = next?.password ?? '';
        _rememberMe = next != null;
      });
    }
    showToast(
      context,
      AppLocalizations.of(
        context,
      )!.profileAccountRemovedToast(credential.username),
    );
  }

  Future<void> _goWebLogin() async {
    final result = await context.pushNamed<bool>(AppRoutes.webviewLogin);
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _goRegister() async {
    final result = await context.pushNamed<RegisterPrefill>(AppRoutes.register);
    if (result == null || !mounted) return;

    await UserManager().saveCredentials(result.username, result.password);
    if (!mounted) return;
    setState(() {
      _rememberMe = true;
      _error = null;
      _usernameCtrl.text = result.username;
      _passwordCtrl.text = result.password;
    });
    showToast(
      context,
      AppLocalizations.of(context)!.profileRegisterSuccessLoginToast,
    );
  }

  Future<void> _openOfficialRegister() async {
    final uri = _useCopyLogin ? _copyMangaRegisterUri : _hotMangaRegisterUri;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showToast(
        context,
        AppLocalizations.of(context)!.profileOpenOfficialRegisterFailed,
        isError: true,
      );
    }
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.profileUsernamePasswordRequired);
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
      setState(() {
        _error = '${l10n.profileLoginFailedProxyHint}\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _showTokenLoginDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var tokenDraft = '';
    var dialogLoading = false;
    String? dialogError;

    final loggedIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (dialogLoading) return;
            final token = tokenDraft.trim();
            if (token.isEmpty) {
              setDialogState(() => dialogError = l10n.profileTokenRequired);
              return;
            }

            setDialogState(() {
              dialogLoading = true;
              dialogError = null;
            });

            try {
              // Temporarily save token so API requests include Authorization.
              await _user.saveLogin(
                token: token,
                userId: '',
                username: '',
                nickname: '',
                avatar: '',
              );
              // Fetch user info with token to validate it.
              final info = await _api.user.getUserInfo();
              await _user.saveLogin(
                token: token,
                userId: info['user_id']?.toString() ?? '',
                username: info['username']?.toString() ?? '',
                nickname:
                    info['nickname']?.toString() ??
                    info['username']?.toString() ??
                    '',
                avatar: info['avatar']?.toString() ?? '',
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            } catch (e) {
              // Invalid token; clear it.
              await _user.logout();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                dialogError = '${l10n.profileTokenInvalidOrExpired}\n$e';
                dialogLoading = false;
              });
            }
          }

          return PopScope(
            canPop: !dialogLoading,
            child: AlertDialog(
              title: Text(l10n.profileTokenLoginEntry),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      autofocus: true,
                      enabled: !dialogLoading,
                      onChanged: (value) => tokenDraft = value,
                      decoration: InputDecoration(
                        labelText: l10n.profileTokenLabel,
                        prefixIcon: const Icon(Icons.key),
                        hintText: l10n.profileTokenHint,
                        border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancelButton),
                ),
                FilledButton(
                  onPressed: dialogLoading ? null : submit,
                  child: dialogLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.profileLoginButton),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (loggedIn == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 400.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileLoginTitle),
        actions: [
          IconButton(
            tooltip: l10n.profileTokenLoginEntry,
            onPressed: _loading ? null : _showTokenLoginDialog,
            icon: const Icon(Icons.key),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 24, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._buildAccountPasswordForm(context, cs),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      AppLocalizations.of(context)!.profileLoginButton,
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
            // Hotmanga register only for account-password + hot source.
            if (!_useCopyLogin) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _goRegister,
                  child: Text(l10n.profileRegisterButton),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton.icon(
                key: ValueKey(
                  _useCopyLogin
                      ? 'official-register-copy'
                      : 'official-register-hotmanga',
                ),
                onPressed: _loading ? null : _openOfficialRegister,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(
                  _useCopyLogin
                      ? l10n.profileCopyMangaLabel
                      : l10n.profileHotMangaLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAccountPasswordForm(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final visibleSavedCredentials = _visibleSavedCredentials;
    return [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text(l10n.profileHotCredentialLabel),
            icon: const Icon(Icons.phone_android, size: 18),
          ),
          ButtonSegment(
            value: true,
            label: Text(l10n.profileCopyCredentialLabel),
            icon: const Icon(Icons.language, size: 18),
          ),
        ],
        selected: {_useCopyLogin},
        onSelectionChanged: (v) => _selectLoginSource(v.first),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (visibleSavedCredentials.isNotEmpty) ...[
        Column(
          children: [
            for (var i = 0; i < visibleSavedCredentials.length; i++) ...[
              _buildSavedCredentialCard(context, visibleSavedCredentials[i]),
              if (i != visibleSavedCredentials.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      TextField(
        controller: _usernameCtrl,
        decoration: InputDecoration(
          labelText: l10n.profileUsernameLabel,
          prefixIcon: const Icon(Icons.person_outline),
          border: OutlineInputBorder(borderRadius: AppRadius.mdR),
        ),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: AppSpacing.lg),
      TextField(
        controller: _passwordCtrl,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: l10n.profilePasswordLabel,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          border: OutlineInputBorder(borderRadius: AppRadius.mdR),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _login(),
      ),
      const SizedBox(height: AppSpacing.sm),
      CheckboxListTile(
        value: _rememberMe,
        onChanged: (v) => setState(() => _rememberMe = v ?? false),
        title: Text(l10n.profileRememberAccountLabel),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      if (_useCopyLogin) ...[
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _loading ? null : _goWebLogin,
          icon: const Icon(Icons.language),
          label: Text(l10n.profileWebLoginButton),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          ),
        ),
      ],
    ];
  }
}

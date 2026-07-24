import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/toast.dart';

class RegisterPrefill {
  final String username;
  final String password;

  const RegisterPrefill({required this.username, required this.password});
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static final _hotMangaRegisterUri = Uri.parse(
    'https://m.manga2026.xyz/v2h5/register',
  );
  static Uri get _copyMangaRegisterUri => Uri.parse(
    'https://${UserManager().copyLoginHost}/web/login/loginByAccount',
  );
  List<String> _fallbackQuestions(AppLocalizations l10n) => [
    l10n.profileFallbackQuestionWife,
    l10n.profileFallbackQuestionFriend,
    l10n.profileFallbackQuestionBestFriendCount,
    l10n.profileFallbackQuestionParentName,
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
      final questions = await _api.user.getSecurityQuestions();
      if (!mounted) return;
      final fallbackQuestions = _fallbackQuestions(
        AppLocalizations.of(context)!,
      );
      final availableQuestions = questions.isNotEmpty
          ? questions
          : fallbackQuestions;
      setState(() {
        _questions = availableQuestions;
        _selectedQuestion = availableQuestions.first;
        _loadingQuestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final fallbackQuestions = _fallbackQuestions(
          AppLocalizations.of(context)!,
        );
        _questions = fallbackQuestions;
        _selectedQuestion = fallbackQuestions.first;
        _loadingQuestions = false;
        _error = null;
      });
    }
  }

  Future<void> _register() async {
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    final answer = _answerCtrl.text.trim();

    if (username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        answer.isEmpty) {
      setState(() => _error = l10n.profileRegisterInfoRequired);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = l10n.profilePasswordMismatch);
      return;
    }
    if (_selectedQuestion == null || _selectedQuestion!.isEmpty) {
      setState(() => _error = l10n.profileSecurityQuestionRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _api.user.register(
        username: username,
        password: password,
        question: _selectedQuestion!,
        answer: answer,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        RegisterPrefill(username: username, password: password),
      );
    } catch (e) {
      String msg = l10n.profileRegisterFailed;
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

  Future<void> _openOfficialRegister(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showToast(
        context,
        AppLocalizations.of(context)!.profileOpenOfficialRegisterFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 420.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.profileRegisterHotMangaAccountButton,
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 24, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.profileUsernameLabel,
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
                labelText: AppLocalizations.of(context)!.profilePasswordLabel,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.profileConfirmPasswordLabel,
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loadingQuestions)
              const Center(child: ExpressiveLoadingIndicator())
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedQuestion,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.profileSecurityQuestionLabel,
                  prefixIcon: const Icon(Icons.help_outline),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
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
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _answerCtrl,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.profileSecurityAnswerLabel,
                  prefixIcon: const Icon(Icons.shield_outlined),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _register(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            if (!_loadingQuestions && _questions.isEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: _loadQuestions,
                icon: const Icon(Icons.refresh),
                label: Text(
                  AppLocalizations.of(
                    context,
                  )!.profileReloadSecurityQuestionsButton,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              onPressed: _submitting || _loadingQuestions ? null : _register,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      AppLocalizations.of(context)!.profileRegisterButton,
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppLocalizations.of(context)!.profileOfficialRegisterPrompt,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_hotMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    AppLocalizations.of(context)!.profileHotMangaLabel,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_copyMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    AppLocalizations.of(context)!.profileCopyMangaLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

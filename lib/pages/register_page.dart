import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
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
  static final _copyMangaRegisterUri = Uri.parse(
    'https://www.mangacopy.com/web/login/loginByAccount',
  );
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
      final questions = await _api.user.getSecurityQuestions();
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

  Future<void> _openOfficialRegister(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showToast(context, '无法打开官网注册页', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 420.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(title: const Text('注册热辣漫画账号')),
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
            const SizedBox(height: 12),
            Text(
              '去官网注册',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_hotMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('热辣漫画'),
                ),
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_copyMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('拷贝漫画'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
